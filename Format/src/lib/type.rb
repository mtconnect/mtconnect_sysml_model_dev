$: << File.dirname(__FILE__)

require 'logger'
require 'relation'
require 'extensions'
require 'operation'
require 'lazy_pointer'
require 'diagram'

class Type
  include Extensions
  
  attr_reader :name, :id, :type, :model, :parent, :children, :relations, :stereotypes, :is_subtype,
              :constraints, :extended, :literals, :invariants, :classifier, :assoc, :xmi, :subtypes, :multiplicity, :optional,
              :operations
  attr_accessor :documentation

  attr_writer :is_subtype
  
  class Literal
    include Extensions
    
    attr_reader :pid, :name, :value, :description, :stereotypes, :owner

    @@literals = Hash.new
    
    def self.literal_for_id(id)
      @@literals[id]
    end
    
    def initialize(owner, id, name, value, description, suffix = '', stereotypes)
      @owner, @pid, @name, @value, @description, @stereotypes = owner, id, name, value, description, stereotypes
      base = name.gsub('_', '').downcase

      @@literals[@pid] = self
      LazyPointer.register(id, self)
    end
  end

  @@types_by_id = {}
  @@types_by_name = {}
  @@terms_by_name = {}

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

  def self.term_for_name(name)
    @@terms_by_name[name]
  end

  def self.add_free_association(model, assoc)
    case assoc['xmi:type']
    when 'uml:Association'
      $logger.debug "Adding free association: #{assoc['name'].inspect} for #{assoc['xmi:id']}"

      if assoc['name'] and !assoc['name'].empty?
        model.class.type_class.new(model, assoc)      
      else
        comment = assoc.at('./ownedComment')
        doc = comment['body'].gsub(/<[\/]?[a-z]+>/, '') if comment and comment.key?('body')
        
        if doc
          if oend = assoc.at('./ownedEnd')
            if tid = oend['type']
              owner = LazyPointer.new(tid)
              aid = oend['association']
              owner.lazy { owner.relation_by_assoc(aid).documentation = doc }
            end
          end
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
    LazyPointer.resolve
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

    find_operations
    
    @abstract = e['isAbstract'] || false
    @literals = Hash.new

    @aliased = false

    if @type == 'uml:Enumeration' and defined? e.ownedLiteral
      collect_enumerations
    end

    @relations = collect_attributes || []
    @constraints = collect_constraints(@xmi)
    @invariants = {}
    @children = []

    # puts "Adding type #{@name} for id #{@id}"
    @@types_by_id[@id] = self

    if @type == 'uml:Class'
      if @model.root.name == 'Glossary'
        @@terms_by_name[@name] = self
      else
        @@types_by_name[@name] = self
      end
    end

    LazyPointer.register(@id, self)
    
    @classifier = nil
    if @type == 'uml:InstanceSpecification'
      klass = @xmi.at('./classifier')
      @classifier = LazyPointer.new(klass['xmi:idref']) if klass
      @name = '' unless @name
    else
      raise "Unknown name for #{@xmi.to_s}" unless @name
    end

    @model.add_type(self)
  end

  def find_operations
    @operations = @xmi.xpath('./ownedOperation').map do |op|
      next unless op['xmi:type'] == 'uml:Operation'    
      Operation.new(self, op)
    end.compact
  end

  def collect_attributes
    @xmi.element_children.map do |r|
      if (r.name != 'ownedLiteral' and r.name != 'ownedAttribute') or r['type']
        Relation.create_association(self, r)
      end
    end.compact   
  end

  def resolved?
    true
  end

  def abstract?
    @abstract
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
        @literals[name] = Literal.new(self, id, name, value, description, suffix, stereotypes)
        break
      else
        name, value = lit['name'].sub(/\^/,'\^').split('=')
        description = xmi_documentation(lit)
        id = lit['xmi:id']
        stereotypes = xmi_stereotype(lit)
        @literals[name] = Literal.new(self, id, name, value, description, suffix, stereotypes)
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

  def is_aliased?
    @aliased
  end

  def enumeration?
    @type == 'uml:Enumeration'
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
    return @parent if defined? @parent
    
    @parent = nil
    glossary = @model.root.name == 'Glossary'
    @relations.each do |r|
      if r.is_a?(Relation::Generalization)
        if r.target
          target_glossary = r.target.type.model.root.name == 'Glossary'
          if glossary == target_glossary
            @parent = r.target.type
            break
          end
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
    return @introduced if defined? @introduced

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

  def deprecated
    introduced
    super
  end

  def add_operations
    return if @operations.empty?
  end
end
