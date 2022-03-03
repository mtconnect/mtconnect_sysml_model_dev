$: << File.dirname(__FILE__)

require 'extensions'

module Relation
  @@connections = {}
  
  def self.clear
  end


  @@unhandled = Set.new(%w{memberEnd classifier Extension ownedConnector templateBinding ownedTemplateSignature ownedBehavior})
  def self.create_association(owner, r)

    
    return nil if @@unhandled.include?(r.name)

    case r['xmi:type']
    when 'uml:Generalization'
      Generalization.new(owner, r)
      
    when 'uml:Realization'
      Realization.new(owner, r)
      
    when 'uml:Dependency'
      Dependency.new(owner, r)
      
    when 'uml:Property'
      if r['association']
        Association.new(owner, r)
      else
        Attribute.new(owner, r)
      end
      
    when 'uml:Association', 'uml:Link'
      Association.new(owner, r)
      
    when 'uml:Constraint'
      Constraint.new(owner, r)
      
    when 'uml:Slot'
      Slot.new(owner, r)
      
    when 'uml:Comment', 'uml:Operation'
      nil

    else
      $logger.error "!! Unknown relation type: #{r.name} :: #{r['xmi:id']} - #{r['xmi:type']} for #{owner.name}"
      nil
    end
  end

  class Constraint
    include Extensions
    
    attr_reader :owner, :name, :specification, :documentation, :assoc, :target, :type
                
    def initialize(owner, r)
      @name = r['name']
      @specification = r['specification']
      @type = r['xmi:type']
    end
  end

  class Relation
    include Extensions
    
    attr_reader :id, :name, :type, :xmi, :multiplicity, 
                :source, :target, :owner, :stereotypes, :visibility, :association_name,
                :constraints, :assoc, :redefinesProperty, :default, :association_doc
    attr_accessor :documentation

    class Connection
      attr_accessor :name, :type, :type_id, :multiplicity
      
      def initialize(name, type)
        @multiplicity = nil
        @name = name
        @type = type
      end

      def introduced
        nil
      end

      def deprecated
        nil
      end

      def resolve_type
        if @type.resolved?
          @type_id = @type.id
          true
        else
          false
        end
      end
    end
    
    def initialize(owner, r)
      @owner = owner
      @id = r['xmi:id']
      @name = r['name']
      @type = r['xmi:type']
      @xmi = r
      @constraints = {}
      
      @multiplicity, @optional = get_multiplicity(r)
      @assoc = r['association']
      @visibility = r['visibility'] ? r['visibility'] : 'public'

      @stereotypes = xmi_stereotype(r)
      @documentation = xmi_documentation(r)

      $logger.debug "       -- :: Creating Relation #{@stereotypes} #{@name} #{@id} #{@assoc}" 
      
      @source = Connection.new('Source', owner)
      @source.multiplicity = @multiplicity
      @target = nil

      LazyPointer.register(@id, self)
    end

    def value
      nil
    end

    def final_target
      @target
    end

    def is_optional?
      @optional
    end
    
    def is_property?
      false
    end

    def is_reference?
      false
    end

    def resolve_types
      if @target.nil?
        $logger.error "    !!!! cannot resolve type for #{@owner.name}::#{@name} no target"
      else
        unless @target.resolve_type or @target.type.internal?
          raise "    !!!! cannot resolve target for #{@owner.name}::#{@name} #{self.class.name}"
        end
      end

      unless @source.resolve_type
        raise "    !!!! cannot resolve source for #{@owner.name}::#{@name} #{self.class.name}"
      end
    end

    def is_array?
      @multiplicity =~ /\.\.\*/
    end
    
    def is_optional?
      @optional
    end

    def get_value(a, ele)
      v = a.at("./#{ele}")
      if v
        if v['xmi:type'] == 'uml:LiteralBoolean'
          return v['value'] || 'false'
        else
          b = v.at(".//body")
          if b
            return b.text
          elsif v['value']
            return v['value']
          end
        end
        if id = v['instance']
          
          if lit = Type::Literal.literal_for_id(id)
            lit.name
          elsif t = Type.type_for_id(id)
            t.name
          else
            # puts "!!! Scanning for #{id}"
            LazyPointer.new(id)
            # puts Thread.current.backtrace.join("\n")
            # a.document.root.at("//*[@xmi:id='#{id}']")['name']
          end
        end
      end
    end
  end
  
  class Association < Relation
    attr_reader :final_target, :association, :assoc_type
    
    class End < Connection
      include Extensions
      
      attr_accessor :name, :optional, :navigable, :xmi
      
      def initialize(e, type)
        super(e['name'], type)

        @multiplicity, @optional = get_multiplicity(e)
        @navigable = false
        @xmi = e
      end

      def is_navigable?
        @navigable
      end
      
      def is_optional?
        @optional
      end
    end

    class Assoc
      include Extensions

      attr_reader :name, :type, :documentation, :stereotypes, :is_derived
      
      def initialize(e)
        @name = e['name']
        @type = e['xmi:type']
        @documentation = xmi_documentation(e)
        @stereotypes=  xmi_stereotype(e)
      end
    end
    
    def initialize(owner, r)
      super(owner, r)

      tid = r['type']
      @final_target = @target = End.new(r, LazyPointer.new(tid))
      
      aid = r['association']
      assoc = r.document.at("//packagedElement[@xmi:id='#{aid}']")      
      @association = Assoc.new(assoc)
      @redefinesProperty = r.at('./redefinedProperty') ? true : false    
      
      src = assoc.at('./ownedEnd')
      return if not src
      
      @source = End.new(src, owner)

      if @association.type == 'uml:AssociationClass'
        @target = End.new(r, LazyPointer.new(aid))
      end

      @name = @target.name || @name || @source.name
      @multiplicity = @target.multiplicity
      @optional = @target.optional

      @constraints = collect_constraints(assoc)
    end

    def final_target
      @final_target
    end

    def is_reference?
      true
    end

    def link_target(reference, type)
      @target = Connection.new(reference, type)
    end

    def resolve_types
      super

      if !@target.equal?(@final_target)
        unless @final_target.resolve_type or @final_target.type_id =~ /^EA/
          raise "    !!!! cannot resolve target for #{@owner.name}::#{@name} #{self.class.name}"
        end
      end
      
    end
  end

  class Attribute < Relation
    
    def initialize(owner, a)
      super(owner, a)
      return if not a['name']
      
      @name = a['name']
      @default = get_value(a, 'defaultValue')

      @redefinesProperty = a.at('./redefinedProperty') ? true : false
      
      @stereotypes = xmi_stereotype(a)
      @documentation = xmi_documentation(a)

      $logger.debug "  Searching for docs for #{owner.name}::#{name}"

      type = a['type']
      @target = Connection.new('Target', LazyPointer.new(type))

    rescue
      $logger.error "Error creating relation: #{a.to_s}"
      raise
    end

    def value
      @default
    end
    
    def is_property?
      true
    end

    def is_reference?
      !is_attribute?
    end    

  end

  class Dependency < Relation
    def initialize(owner, r)
      unless owner
        cli = r.at("./client")
        cid = cli['xmi:idref']

        owner = LazyPointer.new(cid)
      end
      
      super(owner, r)
      
      sup = r.at("./supplier")
      sid = sup['xmi:idref']

      @target = Connection.new('Target', LazyPointer.new(sid))
    end

    def reflow(source, target)
      $logger.debug " --- Reflowing Dependency: #{source.id} -> #{target.id}"
      @source = Connection.new('Source', source)
      @target = Connection.new('Target', target)
    end
  end

  class Generalization < Relation
    def initialize(owner, r)
      super(owner, r)
      
      @target = Connection.new('Target', LazyPointer.new(r['general'])) if r['general']
      @name = 'Supertype' unless @name
    end

    def resolve_types
      super
    end

  end
  
  class Realization < Dependency
    def initialize(owner, r)
      super(owner, r)
    end

  end

  class Slot < Relation
    def initialize(owner, a)
      super(owner, a)
      @target_id = a['definingFeature']
      @target = @relation = nil
      @value = get_value(a, 'value')
    end

    def value
      @value
    end

    def is_array?
      @value and @value[0] == '['
    end

    def is_property?
      true
    end

    def resolve_types
      unless @relation
        @relation = owner.classifier.relation_by_id(@target_id)        
        raise " -- Relation not resolved for #{@target_id}" unless @relation
        
        @name = @relation.name
        @target = @relation.target
      end
      if LazyPointer === @value
        @value = @value.name
      end
      
    rescue
      $logger.error "Cannot resolve type #{@owner.name}::#{@name} #{@xmi.to_s}"
      $logger.error $!
      raise
    end
  end
end
