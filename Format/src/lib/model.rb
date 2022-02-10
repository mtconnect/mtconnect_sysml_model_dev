$: << File.dirname(__FILE__)

require 'type'
require 'stereotype'
require 'lazy_pointer'

class Model
  include Extensions
  
  attr_reader :name, :documentation, :types, :xmi, :parent_name, :stereotypes, :children, :parent

  @@skip_models = {}
  @@models = {}

  def self.clear
    @@models.clear
    @@skip_models.clear
    Stereotype.clear
  end
  
  def self.type_class
    raise "Must use subtype"
  end

  def self.skip_models=(models)
    @@skip_models = models
  end

  def self.models
    @@models
  end

  def self.model_for_name(name)
    @@models[name]
  end

  def self.clear
    @@models.clear
    LazyPointer.clear
  end

  def initialize(parent, e)
    @id = e['xmi:id']
    @name = e['name']
    @type = e['xmi:type']
    @xmi = e
    @types = []
    @children = []

    @parent = @parent
    if @parent
      @parent_name = @parent.name
      @parent.children << self
    end
    @documentation = xmi_documentation(e)
    @stereotypes = xmi_stereotype(e)

    @@models[@name] = self

    LazyPointer.register(@id, self)
  end

  def root
    parent.nil? ? self : parent.root
  end

  def model
    self
  end

  def add_type(t)
    @types << t
  end

  def short_name
    @name.gsub(/[ _]/, '')
  end

  def to_s
    @name
  end

  def find_data_types(depth = 0)
    $logger.debug "#{'  ' * depth}Finding data types for #{@name}"
    
    @xmi.xpath('./packagedElement[@xmi:type="uml:DataType" or @xmi:type="uml:Enumeration" or @xmi:type="uml:PrimitiveType"]').each do |e|
      $logger.debug "#{'  ' * depth}#{@name}::#{e['name']} #{e['xmi:type']}"
      self.class.type_class.new(self, e)
    end    

    @xmi.xpath('./packagedElement[@xmi:type="uml:Package" or @xmi:type="uml:Profile"]').each do |e|
      unless @@skip_models.include?(e['name'])
        $logger.debug "Recursing model for enumerations: #{e['name']}"
        model = self.class.new(self, e)
        model.find_data_types(depth + 1)
      else
        $logger.info "Skipping model #{e['name']}"
      end
    end
  end

  def find_definitions(depth = 0)
    $logger.debug "#{'  ' * depth}Finding stereotypes for '#{@name}' '#{@type}'"

    @xmi.xpath('./packagedElement[@xmi:type="uml:Class" or @xmi:type="uml:Object" or @xmi:type="uml:Stereotype" or @xmi:type="uml:AssociationClass" or @xmi:type="uml:InstanceSpecification"]', $namespaces).each do |e|
      $logger.debug "#{'  ' * depth}#{@name}::#{e['name']} #{e['xmi:type']}"
      self.class.type_class.new(self, e)
    end

    @xmi.xpath('./packagedElement[@xmi:type="uml:Package" or @xmi:type="uml:Profile"]').each do |e|
      unless @@skip_models.include?(e['name'])
        $logger.debug "Recursing model: #{e['name']}"
        model = @@models[e['name']]
        model.find_definitions(depth + 1)
      else
        $logger.info "Skipping model #{e['name']}"
      end
    end

    $logger.debug "Getting associations for #{@name}"
    @xmi.xpath('./packagedElement[@xmi:type="uml:Realization" or @xmi:type="uml:Dependency" or @xmi:type="uml:Association" or @xmi:type="uml:InformationFlow"]').each do |e|
      self.class.type_class.add_free_association(self, e)
    end

    if depth == 0
      Type.connect_model
    end
  end
  
end

