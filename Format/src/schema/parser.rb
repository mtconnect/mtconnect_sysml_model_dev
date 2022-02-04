
require 'set'

INF = 0xFFFFFFFF

module Annotation
  def annotation
    unless @checked_glossary
      if Glossary.terms.include?(@name.to_s)
	    @annotation = Glossary.terms[@name.to_s]
	  end
      @checked_glossary = true
    end
    @annotation
  end
end

class Schema
  module Standards
    def all_standards(fill = false)
      if !@standards.empty?
        @schema.standards.map { |s| [s, @standards[s]] }
      elsif fill
        Array.new(@schema.standards.length)
      else
        []
      end
    end

    def standards_header
      @schema.standards
    end
    
    def standards(stands)
      stands.keys.each { |s| @schema.add_standard(s) }
      @standards.merge! stands
    end
  end
  
  attr_reader :packages, :derived, :importing
  attr_accessor :top, :namespace, :urn, :license, :version, :importing
  
  def initialize(script)
    @importing = false
    @packages = []
    @urn = ''
    @types = []
    @imports = []
    @xsimports = []
    @type_map = { }
    @derived = Set.new
    @top = nil
    @license = nil
    @namespace = 'ns'
    @standards = Set.new
    instance_eval script, 'Top'
  end

  def load(file)
    file = file + '.msd' unless file =~ /\.[a-z]+$/
    instance_eval(File.read(file), file)
  end

  def derived?(type)
    @derived.member?(type)
  end
  
  def type(name, annotation, parent = 'string', attr = false, &block)
    BasicType.new(self, name, annotation, parent, attr, &block)
  end
  
  def attr(name, annotation, parent = 'string', attr = true, &block)
    BasicType.new(self, name, annotation, parent, attr, &block)
  end
  
  def enum(name, annotation, parent = 'string', attr = true, &block)
    ControlledVocabulary.new(self, name, annotation, parent, attr, &block)
  end
  
  def package(name, annotation, &block)
    @packages << Package.new(self, name, annotation, &block)
  end
  
  # Import another schema
  def import(name, location)
    @imports << ImportedSchema.new(self, name, location)
  end

  def xsimport(name, namespace, location)
    @xsimports << [name, namespace, location]
  end

  def add_type(name, type)
    @types << type
    @type_map[name] = type
  end

  def types
    @types
  end

  def type(name)
    @type_map[name]
  end
  
  def check_type(name)
    raise "Cannot resolve type #{name}" unless @type_map[name]
  end

  def standards
    unless defined? @ordered_standards
      @ordered_standards = @standards.to_a.map { |s| s.to_s }.sort.map { |s| s.to_sym }
    end
    @ordered_standards
  end

  def add_standard(stand)
    @standards << stand
  end
  
  class ImportedSchema
    attr_accessor :namespace, :urn, :license, :version, :top
    attr_reader :location
    
    undef :load
    if RUBY_VERSION < '1.9.2'
      undef :type
    end
    
    def initialize(schema, file, location)
      old_importing, schema.importing = schema.importing, self
      @schema = schema
      @location = location
      file = file + '.msd' unless file =~ /\.[a-z]+$/
      puts "Importing file: #{file}"
      Dir.chdir(File.dirname(file)) do
        instance_eval(File.read(File.basename(file)), file)
      end
      schema.importing = old_importing
    end
        
    # Forward all other methods accept for the settings to schema
    def method_missing(method, *args, &block)
      @schema.send(method, *args, &block)
    end
  end
  
  class Type
    attr_reader :name, :parent, :imported
    attr_reader :attr, :schema
    attr_accessor :version

    include Standards
    include Annotation

    def initialize(schema, name, annotation, parent = nil)
      @name, @annotation, @parent = name, annotation, parent
      @schema = schema
      @attr = false
      @standards = { }
      @schema.add_type(name, self)
      @imported = schema.importing
    end
    
    def resolve
    end

    def build_hierarchy
    end
  end

  class BasicType < Type
    attr_reader :annotation, :pattern, :facet, :attr, :union, :list

    def initialize(schema, name, annotation, parent = 'string', attr = true, &block)
      super(schema, name, annotation, parent)
      @annotation, @attr = annotation, attr
      instance_eval &block if block
    end

    def facet(value)
      @facet = value
    end

    def pattern(value)
      @pattern = value
    end

    def union(*types)
      @union = types
    end

    def list(type)
      @list = type
    end
  end

  class ControlledVocabulary < Type
    attr_reader :values, :attr, :extensible
    include Annotation
    
    class Value
      attr_reader :name, :annotation
      include Standards
      include Annotation
      
      def initialize(schema, name, annotation, &block)
        @schema, @name, @annotation = schema, name, annotation
        @standards = { }
        instance_eval &block if block
      end
    end
    
    def initialize(schema, name, annotation, parent = 'enum', attr = true, &block)
      super(schema, name, annotation, parent)
      @name, @annotation, @parent, @attr = name, annotation, parent, attr
      @values = []
      @extensible = false
      instance_eval &block
    end

    def extensible
      @extensible = true
    end

    def value(name, annotation, &block)
      unless annotation
        raise "Cannot find annotation for #{name}"
      end
        
      @values << Value.new(@schema, name, annotation, &block)
    end
  end
  
  class Package
    attr_reader :elements, :enums, :basic_types, :name, :annotation, :schema

    include Standards
    
    def initialize(schema, name, annotation, &block)
      #puts "Creating package #{name}"
      @schema, @name, @annotation = schema, name, annotation
      @elements = []
      @basic_types = []
      @enums = []
      @imported = schema.importing
      @standards = { }
      instance_eval &block
    end

    def type(name, annotation = nil, parent = nil, &block)
      if Symbol === annotation
        parent = annotation
        annotation = nil
      end
      @elements << (e = Element.new(@schema, name, annotation, parent, &block))
      e
    end
    
    def element(name, annotation, parent = nil, &block)
      element = Element.new(@schema, name, annotation, parent, &block)
      element.force_element = true
      @elements << element
      element
    end

    def basic_type(name, annotation, parent = 'string', attr = false, &block)
      @basic_types << (t = BasicType.new(@schema, name, annotation, parent, attr, &block))
      t
    end
    
    def attr(name, annotation, parent = 'string', attr = true, &block)
      BasicType.new(@schema, name, annotation, parent, attr, &block)
    end
  
    def enum(name, annotation, parent = 'NMTOKEN', attr = true, &block)
      @enums << (e = ControlledVocabulary.new(@schema, name, annotation, parent, attr, &block))
      e
    end

    def attrs(name, annotation = nil, parent = nil, &block)
      @elements << (g = AttributeGroup.new(@schema, name, annotation, parent, &block))
      g
    end  
  end

  class Element < Type
    attr_reader :members, :parent, :polymorphic
    attr_accessor :force_element
    include Annotation

    def initialize(schema, name, annotation, parent = nil, &block)
      super(schema, name, annotation, parent)
      @name, @annotation, @parent = name, annotation, parent
      @polymorphic = @mixed = @force_element = @abstract = false
      @ordered = false
      @members = []
      @children = []
      @schema.derived << @parent if @parent and @parent != :abstract
      instance_eval &block if block
    end
    
    def to_s
      "Element: #{@name}:#{@parent} #{@annotation}"
    end
    
    def polymorphic
      @polymorphic = true
    end

    def abstract
      @abstract = true
      @polymorphic = true
    end
    
    def mixed
      @mixed = true
    end

    def ordered
      @ordered = true
    end

    def abstract?
      @abstract
    end
    
    def polymorphic?
      @polymorphic
    end
    
    def mixed?
      @mixed
    end

    def subtype?
      !@parent.nil?
    end

    def resolve_parent
      if @parent
        par = @schema.type(@parent)
        raise "Cannot resolve parent type #{@parent}" unless par
      end
      par
    end

    def has_subtypes?
      @schema.derived.include? @name
    end

    def abstract_parent?
      pnt = resolve_parent
      while pnt
        return true if pnt.abstract?
        pnt = pnt.resolve_parent
      end
      false
    end
    
    def polymorphic_parent?
      pnt = resolve_parent
      while pnt
        return true if pnt.polymorphic?
        pnt = pnt.resolve_parent
      end
      false      
    end

    def member(name, annotation, occurrence = nil, type = nil, &block)
      type, occurrence = occurrence, nil if Symbol === occurrence
      @members << Member.new(@schema, name, annotation, occurrence, type, &block)
    end
    
    def attribute(name, annotation, occurrence = nil, type = nil, &block)
      type, occurrence = occurrence, nil if Symbol === occurrence
      mem = Member.new(@schema, name, annotation, occurrence, type, &block)
      mem.attribute = true
      @members << mem
    end
    
    def element(name, annotation, occurrence = nil, type = nil, &block)
      type, occurrence = occurrence, nil if Symbol === occurrence
      mem = Member.new(@schema, name, annotation, occurrence, type, &block)
      mem.attribute = false
      @members << mem
    end
    
    def value(annotation, type, &block)
      @members << Member.new(@schema, :Value, annotation, nil, type, &block)
    end

    def all_subtypes(base, occurrence = 0..INF)
      @members << Subtypes.new(@schema, base, occurrence)
    end

    def choice(occurrence = 1, &block)
      @ordered = true
      @members << Choice.new(@schema, occurrence, &block)
    end
    
    def at_least_one(occurrence = 1, &block)
      @ordered = true
      c = Choice.new(@schema, occurrence, &block)
      m, mc = c.members, c.members.dup
      raise "at least one must have more than one member" unless mc.size > 1
      m.clear
      nm = mc.shift
      while !mc.empty?
        s = ChoiceSet.new(@schema)
        s.members << nm.dup
        mc.each do |om|
          om = om.dup
          om.occurrence = 0..1
          s.members << om
        end
        m << s
        nm = mc.shift        
      end
      m << nm.dup
      @members << c
    end

    def <=>(other)
      @name <=> other.name
    end

    def restriction?(other)
      other_elems = other.members.select { |m| !m.attribute? and !m.is_a? Choice }.map { |m| m.name }
      elems = @members.select { |m| !m.attribute? and !m.is_a? Choice }.map { |m| m.name }
      if other_elems.empty? or elems.empty?
        false
      else
        other_elems == elems
      end
    end
    
    def children(deep = false)
      children = @children.dup
      if deep
        children.concat(@children.map { |c| c.children }.flatten)
      end
      children
    end
    
    def add_child(child)
      @children << child
    end
    
    def build_hierarchy
      if @parent
        unless @schema.type(@parent)
          raise "Cannot find parent '#{@parent.inspect}' for '#{self.name}'"          
        end
        @schema.type(@parent).add_child(self)
      end
    rescue
      raise "Could not add child to '#{@parent.inspect}' for '#{self.name}': #{$!} "
    end
    
    def resolve
      @members.each { |m| m.resolve(self.name) }
    end

    def value_member
      members.each { |m| return m if m.is_value? }
      nil
    end
    
  end

  class AttributeGroup < Element
    def initialize(schema, name, annotation, parent = nil, &block)
      super
      @attr = true
    end      
    
    def attribute(name, annotation, occurrence = nil, type = nil, &block)
      super
    end
    alias member attribute
  end
  
  class Member
    include Comparable
    include Annotation
    
    attr_reader :name, :type
    attr_accessor :occurrence, :default, :notQName, :processContents, :namespace, :notNamespace,
      :fixed
    
    INF = 0xFFFFFFFF

    include Standards
    
    def initialize(schema, name, annotation, occurrence = nil, type = nil, &block)
      @schema, @name, @annotation, @type = schema, name, annotation, type
      @occurrence = occurrence
      @type = @name unless @type
      @notQName = @namespace = @notNamespace = nil
      @processContents = 'lax'
      @standards = { }
      @imported = schema.importing
      instance_eval &block if block
    end

    def <=>(other)
      @name <=> other.name
    end

    def resolve_type
      if @type == :any or @type.to_s.include?(':')
        res = @type 
      else
        res = @schema.type(@type)
        unless res
          raise "Cannot resolve type #{@type} for #{@name}"
        end
      end
      res
    end

    def is_value?
      type = resolve_type
      @name == :Value and !type.is_a?(Element)
    rescue
      puts $!
      false
    end

    def attribute?
      if !defined?(@attribute)
        type = @schema.type(@type)
        @attribute = (@name != :Value and @name != :any and
                      (type.nil? or type.attr))
      end
      @attribute
    end
    
    def attribute=(a)
      @attribute = a
    end
    
    def references_polymorphic?
      type = resolve_type
      type and type.is_a? Element and type.polymorphic? and (type.subtype? or type.has_subtypes?)
    end
    
    def resolve(owner)
      @parent = owner
    end
  end

  class Choice < Member
    attr_reader :members
    
    def initialize(schema, occurrence = 1, &block)
      @members = []
      super(schema, 'choice', 'choice', occurrence)
    end

    def member(name, annotation, occurrence = nil, type = nil, &block)
      type, occurrence = occurrence, nil if Symbol === occurrence
      @members << Member.new(@schema, name, annotation, occurrence, type, &block)
    end
    
    def set(occurrence = 1, &block)
      @members << ChoiceSet.new(@schema, occurrence, &block)
    end

    def attribute?
      false
    end

    def resolve_type
      nil
    end
  end
  
  class ChoiceSet < Member
    attr_reader :members
    
    def initialize(schema, occurrence = 1, &block)
      @members = []
      super(schema, 'sequence', 'sequence', occurrence)
    end
    
    def member(name, annotation, occurrence = nil, type = nil, &block)
      type, occurrence = occurrence, nil if Symbol === occurrence
      @members << Member.new(@schema, name, annotation, occurrence, type, &block)
    end
    
    def attribute?
      false
    end

    def resolve_type
      nil
    end
  end
  
  class Subtypes < Choice
    attr_reader :base
    
    def initialize(schema, base, occurrence = 0..INF)
      super(schema, occurrence)
      @base = base
    end
    
    # Add all the members for the type and all the subtypes
    def resolve(owner)
      super
      type = @schema.type(base)      
      children = type.children(true)
      children.each do |child|
        member(child.name, child.annotation)
      end
      member(type.name, type.annotation)
    end
  end
end

