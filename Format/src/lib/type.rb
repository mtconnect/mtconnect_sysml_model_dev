$: << File.dirname(__FILE__)

require 'logger'
require 'relation'
require 'extensions'


class Type
  include Extensions
  
  attr_reader :name, :id, :type, :model, :parent, :children, :relations, :stereotypes, :is_subtype,
              :constraints, :extended, :literals, :invariants, :classifier, :assoc, :xmi, :subtypes, :multiplicity, :optional
  attr_accessor :documentation

  attr_writer :is_subtype
  
  class Literal
    include Extensions
    
    attr_reader :pid, :name, :value, :description, :stereotypes

    @@literals = Hash.new
    
    def self.literal_for_id(id)
      @@literals[id]
    end
    
    def initialize(id, name, value, description, suffix = '', stereotypes)
      @pid, @name, @value, @description, @stereotypes = id, name, value, description, stereotypes
      base = name.gsub('_', '').downcase

      @@literals[@pid] = self
    end
  end

  class LazyPointer
    @@pointers = []

    def self.resolve
      @@pointers.each do |o|
        o.resolve
      end
    end

    def _type
      @type
    end

    def initialize(obj)
      @tid = @type = nil
      @lazy_lambdas = []

      case obj
      when String
        @tid = obj
        @type = Type.type_for_id(@tid)
        @@pointers << self unless @type

        raise "ID required when String" if @tid.nil? or @tid.empty?

      when Type
        @type = obj
        @tid = @type.id

      else
        raise "Pointer created for unknown type: #{obj.class} '#{@tid}' '#{@type}'"
      end
    end

    def lazy(&block)
      if @type
        @type.instance_eval(&block)
      else
        @lazy_lambdas << block
      end
    end

    def id
      @tid
    end

    def resolved?
      !@type.nil?
    end

    def internal?
      @tid =~ /^EA/
    end

    def resolve
      unless @type
        @type = Type.type_for_id(@tid)
        if @type.nil?
          $logger.debug " --> Looking up type for #{@tid}"
          @type = Type.type_for_name(@tid)          
        end
        
        if @type
          @lazy_lambdas.each do |block|
            @type.instance_eval(&block)
          end
        else
          $logger.warn "Warn: Cannot find type for #{@tid}"
        end
      end
      
      !@type.nil?
    end

    def method_missing(m, *args, &block)
      unless @type
        #raise "!!! Calling #{m} on unresolved type #{@tid}" #TODO: template parameters
      else
        @type.send(m, *args, &block)
      end
    end    
  end

  @@types_by_id = {}
  @@types_by_name = {}

  def self.clear
    @@types_by_id.clear
    @@types_by_name.clear
  end

  def self.type_for_id(id)
    @@types_by_id[id]
  end

  def self.type_for_name(name)
    @@types_by_name[name]
  end

  def self.add_free_association(assoc)
    case assoc['xmi:type']
    when 'uml:Association'
      comment = assoc.at('./ownedComment')
      doc = comment['body'].gsub(/<[\/]?[a-z]+>/, '') if comment and comment.key?('body')

      if doc
        oend = assoc.at('./ownedEnd')
        tid = oend['type'] if oend
        owner = LazyPointer.new(tid) if tid
        if owner
          aid = oend['association']
          owner.lazy { owner.relation_by_assoc(aid).documentation = doc }
        end
      end

    when 'uml:InformationFlow'
      rel = assoc.at('./realization')
      if rel
        idref = rel['xmi:idref']
        source = LazyPointer.new(assoc.at('./informationSource')['xmi:idref'])
        target = LazyPointer.new(assoc.at('./informationTarget')['xmi:idref'])

        # Find the relization in the source or target
        source.lazy {
          $logger.debug "   === Finding #{idref} in the source"
          r = relation_by_id(idref)
          r.reflow(source, target) if r
        }
        target.lazy {
          $logger.debug "   === Finding #{idref} in the target"
          r = relation_by_id(idref)
          r.reflow(source, target) if r
        }
      else
        $logger.error "Cannot find realization for #{assoc.to_s}"
      end
      
    when 'uml:Realization'
      $logger.debug " Creating uml:Realization"
      r = Relation::Realization.new(nil, assoc)
      $logger.debug "+ Adding realization #{r.stereotypes} for #{r.is_mixin?} -- #{r.owner.id}"
      $logger.debug "   ++ #{r.owner.name}" if r.owner.resolved?
      r.owner.lazy { self.add_relation(r) }

    when 'uml:Dependency'
      $logger.debug " Creating uml:Dependency"
      r = Relation::Dependency.new(nil, assoc)
      r.owner.lazy { self.add_relation(r) }      
      $logger.debug "+ Adding dependency #{r.stereotypes} for #{r.owner.id}"

    else
      $logger.error "!!! unknown association type: #{assoc['xmi:type']}"
    end
      
  end

  def self.connect_model
    Type::LazyPointer.resolve
    connect_children
    resolve_types
  end

  def self.connect_children
    @@types_by_id.each do |id, type|
      parent = type.get_parent
      parent.add_child(type) if parent
    end
  end

  def self.resolve_types
    @@types_by_id.each do |id, type|
      $logger.debug "     -- Resolving types for #{type.name}"
      #type.resolve_types
      #type.check_mixin
    end
  end
  
  def initialize(model, e)
    @model = model
    @xmi = e
    @id = e['xmi:id']

    @name = e['name']
    
    @subtypes = []
    @visibility = e.key?('visibility') ? e['visibility'] : 'public'
    @multiplicity, @optional = get_multiplicity(e)
    @is_subtype = false
    @documentation = xmi_documentation(e) || ''
    @stereotypes = xmi_stereotype(e)
    
    @type = e['xmi:type']       
    $logger.debug "  -- Creating class #{@stereotypes} #{@name} : #{@type}"
    
    @operations = @xmi.xpath('./ownedOperation').map do |op|
      name = op['name']
      doc = xmi_documentation(op)
      
      $logger.warn "Could not find docs for for #{@name}::#{name}" unless doc
      [name, doc]
    end
    
    @abstract = e['isAbstract'] || false
    @literals = Hash.new

    @aliased = false

    associations = []
    if @type == 'uml:Enumeration' and defined? e.ownedLiteral
      collect_enumerations
    else
      e.element_children.each do |r|
        if r.name != 'ownedAttribute' or r['type']
          associations << Relation.create_association(self, r)
        end
      end
    end
    associations.compact!
   
    @constraints = {}
    @invariants = {}
    @relations = associations

    @children = []

    # puts "Adding type #{@name} for id #{@id}"

    @@types_by_id[@id] = self
    @@types_by_name[@name] = self
    
    @classifier = nil
    if @type == 'uml:InstanceSpecification'
      klass = @xmi.at('./classifier')
      @classifier = LazyPointer.new(klass['xmi:idref']) if klass
    end

    raise "Unknown name for #{@xmi.to_s}" unless @name
    @model.add_type(self)
  end

  def resolved?
    true
  end

  def collect_enumerations
    suffix = ' ' + @name.sub(/^MT/, '').sub(/Type$/, '').downcase
    @xmi.ownedLiteral.each do |lit|
      if Array === lit
        literal, = @xmi.xpath("./ownedLiteral")
        name, value = literal['name'].sub(/\^/,'\^').split('=')
        description = xmi_documentation(literal)
        stereotypes = xmi_stereotype(literal)
        id = literal['xmi:id']
        @literals[name] = Literal.new(id, name, value, description, suffix, stereotypes)
        break
      else
        name, value = lit['name'].sub(/\^/,'\^').split('=')
        description = xmi_documentation(lit)
        id = lit['xmi:id']
        stereotypes = xmi_stereotype(lit)
        @literals[name] = Literal.new(id, name, value, description, suffix, stereotypes)
      end
    end
  end

  def literal(name)
    @literals[name]

  end

  def literals
    @literals.values
  end

  def add_relation(rel)
    @relations << rel
  end

  def inspect
    "<#{@type} #{@name}>"
  end

  def relation(name)
    rel, = @relations.find { |a| a.name == name }
    rel = @parent.relation(name) if rel.nil? and @parent
    rel
  end

  def relation_by_id(id)
    # $logger.debug " Checking #{@name} for relation #{id} parent #{@parent}"
    rel, = @relations.find { |a| a.id == id }
    rel = @parent.relation_by_id(id) if rel.nil? and @parent
    rel
  end

  def relation_by_assoc(id)
    rel, = @relations.find { |a| a.assoc == id }
    rel = @parent.relation_by_assoc(id) if rel.nil? and @parent
    rel
  end

  def is_opc?
    @model.is_opc?
  end

  def is_aliased?
    @aliased
  end

  def enumeration?
    !@literals.empty?
  end

  def resolve_types
    @relations.each do |r|
      r.resolve_types
    end
  end

  def add_child(c)
    @children << c
  end

  def stereotype_name
    if @streotypes
      @streotypes.map { |s| s.to_s }.join(' ')
    else
      ''
    end
  end

  def short_name
    @name.gsub(/[ _]/, '')
  end

  def to_s
    "#{@model}::#{@name} -> #{stereotype_name} #{@type} #{@id}"
  end

  def self.resolve_type(ref)
    type = @@types_by_id[ref]
  end

  def resolve_type(ref)
    Type.resolve_type(ref)
  end

  def resolve_type_name(prop)
    if String === prop
      prop
    else
      type = resolve_type(prop)
      if type
        type.name
      else
        'Unknown'
      end
    end
  end

  def get_attribute_like(name, stereo = nil)
    $logger.debug "getting attribute '#{@name}::#{name}' #{stereo.inspect} #{@relations.length}"
    @relations.each do |a|
      $logger.debug "---- Checking '#{a.name}' '#{a.stereotypes}'"
      if a.name == name and
        (stereo.nil? or (a.stereotypes and a.stereotype =~ stereo))
        $logger.debug "----  >> Found #{a.name}"
        return a
      end
    end
    return @parent.get_attribute_like(name, stereo) if @parent
    nil
  end

  def get_parent
    if !defined?(@parent)
      @parent = nil
      @relations.each do |r|
        if r.is_a?(Relation::Generalization)
          @parent = r.target.type if r.target
        end
      end
    end
    @parent
  end

  def root
    if get_parent.nil?
      self
    else
      @parent
    end
  end

  def is_a_type?(type)
    @name == type or (@parent and @parent.is_a_type?(type))
  end

  def dependencies
    @relations.select { |r| r.class == Relation::Dependency }
  end

  def realizations
    @relations.select { |r| r.class == Relation::Realization }
  end

  def derive_version(stereo, properties)
    properties.split(',').map { |s| s.strip }.map do |s|
      prop = relation(s)
      if prop and prop.value and prop.target.type
        lit = prop.target.type.literal(prop.value)
        if lit
          lit.version_for(stereo)
        end
      end
    end.compact.max
  end

  def introduced
    if defined? @introduced
      @introduced
    else
      super
      if @introduced and @introduced !~ /^[0-9]/
        @version_properties = @introduced
        @introduced = derive_version('normative', @version_properties)

        # Check for deprecated
        unless @deprecated
          @deprecated = version_for('deprecated')
          @deprecated = derive_version('deprecated', @version_properties) unless @deprecated
        end
      end
      @introduced
    end
  end

  def deprecated
    introduced
    super
  end
end
