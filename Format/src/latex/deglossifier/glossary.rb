$: << '.'

require 'treetop'
require 'latex_parser'
require 'csv'

$parser = LatexParser.new

$parser.parse_glossary('./mtc-terms.tex')

$root = './Models'
Dir.mkdir $root unless File.exists?($root)

def pascalize(name)
  name.to_s.split('_').map { |s| s.capitalize }.join('')
end

# Enumerations

CSV.open(File.join($root, 'enumerations.csv'), 'w') do |csv|  
  csv << ['Owner', 'Name', 'OwnedComment']
  $parser.units.sort.each do |u|
    csv << ['UnitEnum', u.name_property, u.description]
  end
  $parser.nativeUnits.sort.each do |u|
    csv << ['NativeUnitEnum', u.name_property, u.description]
  end
  $parser.subtypes.sort.each do |u|
    csv << ['DataItemSubTypeEnum', u.name_property, u.description]
  end
end

# Components

owner = 'Components::ComponentTypes'

CSV.open(File.join($root, 'component_classes.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'ownedComment']
  $parser.components.sort.each do |g|
    csv << [owner, g.name_property, g.description]
  end
end

CSV.open(File.join($root, 'component_gen.csv'), 'w') do |csv|
  csv << ['Generalization', 'Name']
  $parser.components.sort.each do |g|
    par, = g.kind
    res = $parser[par.to_s]
    parent = res.name_property
    if parent == 'Component'
      parent = 'Components::Component'
    else
      parent = "#{owner}::#{parent}"
    end
    csv << [parent, "#{owner}::#{g.name_property}"]
  end
end

owner = 'Components::Compositions::CompositionTypes'

CSV.open(File.join($root, 'composition_classes.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'ownedComment']
  $parser.compositions.sort.each do |g|
    csv << [owner, pascalize(g.name_property), g.description]
  end  
end

CSV.open(File.join($root, 'composition_gen.csv'), 'w') do |csv|
  csv << ['Generalization', 'Name']
  $parser.compositions.sort.each do |g|
    csv << ['Components::Compositions::Composition', "#{owner}::#{pascalize(g.name_property)}"]
  end  
end


CSV.open(File.join($root, 'composition_enum.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'ownedComment']
  $parser.compositions.sort.each do |g|
    csv << ['Components::Compositions::CompositionTypeEnum', g.name_property, g.description]
  end  
end

# Set the static type

CSV.open(File.join($root, 'composition_attributes.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'AttrType', 'Visibility', 'True', 'Type', 'Redefines']
  $parser.compositions.sort.each do |g|
    block = "#{owner}::#{pascalize(g.name_property)}"
    csv << [block, 'type', "Components::Compositions::CompositionTypeEnum", 'public', 'true', 
            g.name_property, "Components::Compositions::Composition::type"]
  end
end

# Observation Types

class Observable
  attr_reader :name, :description, :units, :type, :owner, :sub_type, :kind, :enum

  @@types = Hash.new

  def self.types
    @@types
  end

  def initialize(kind, owner, name, description, units, type, parent, enum, sub_type)
    @kind, @name, @description, @type, @sub_type, @owner, @parent, @enum =
                kind, name, description, type, sub_type, owner, parent, enum

    if units and !units.empty?
      u = $parser[units.to_s]
      if u
        @units = u.name_property.to_s
      else
        puts "Could not find '#{units}'"
        @units = units
      end
    end
    @@types[name] = self
  end

  def parent
    @@types[@parent]
  end

  def qn
    "#{owner}::#{name}"
  end

  def abstract?
    @parent.nil?
  end
end

class Enumeration
  attr_reader :owner, :keys, :name, :values

  @@enumerations = Hash.new

  def self.enums
    @@enumerations
  end

  def self.create(owner, name, values)
    keys = values.map { |v| v.first }.join
    @@enumerations[keys] || Enumeration.new(owner, name, values)
  end
  
  def initialize(owner, name, values)
    @owner, @name, @values =
                   owner, name, values
    @keys = values.map { |v| v.first }.join

    @@enumerations[@keys] = self
  end
  
  def eql?(o)
    @keys == o.keys
  end
  
  def hash
    @keys.hash
  end

  def qn
    "#{owner}::#{@name}"
  end
end

enum_prefix = 'Observations::Events'
observation = 'Observations'

Observable.new('Sample', observation, 'Sample', nil, nil, nil, nil, nil, nil)
Observable.new('Event', observation, 'Event', nil, nil, nil, nil, nil, nil)
Observable.new('Condition', observation, 'Condition', nil, nil, nil, nil, nil, nil)

$parser.samples.concat($parser.events).concat($parser.conditions).sort.uniq.each do |g|
  name = g[:elementname].to_s
  next unless name and !name.empty?

  if g[:units]
    u = $parser[g[:units]]
    units = (u && u.name_property) || g[:units]
  end

  kind = g[:kind].to_s.split(',').select { |s| s =~ /event|sample|condition/ }.first.capitalize
  owner = "#{observation}::#{kind}Types"

  if g[:enumeration]
    values = (g.enumeration.to_s.split(',').map do |en|
                e = $parser[en]
                [e.name_property, e.description]
              end.to_a)

    enumeration = Enumeration.create(owner, "#{name}Enum", values)
  end

  Observable.new(kind, owner, name,
                 g.description, units,
                 g.name_property, kind, enumeration, nil)
  
  subtypes = g[:subtype].to_s
  if subtypes
    vals =  subtypes.split(',')
    vals.each do |v|
      vg = $parser[v.strip]
      if vg
        Observable.new(kind, owner, pascalize(vg.name_property) + name,
                       vg.description, units, g.name_property.to_s, name, nil,
                       vg.name_property.to_s)
      end
    end
  end
end

CSV.open(File.join($root, 'observation_classes.csv'), 'w') do |types|  
  types << ['Owner', 'Name', 'OwnedComment']
  Observable.types.each do |name, observable|
    unless observable.abstract?
      types << [observable.owner, observable.name, observable.description]
    end
  end
end

CSV.open(File.join($root, 'observation_gen.csv'), 'w') do |types|  
  types << ['Generalization', 'Name']
  Observable.types.each do |name, observable|
    unless observable.abstract?
      types << [observable.parent.qn, observable.qn]
    end
  end
end

CSV.open(File.join($root, 'dataitemtype_enums.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'Description']
  Observable.types.each do |name, observable|
    if observable.type and !observable.abstract? and observable.parent.abstract?
      csv << ["DataTypes::#{observable.kind}Enum", observable.type, observable.description]
    end
  end
end

CSV.open(File.join($root, 'observation_attributes.csv'), 'w') do |attrs|
  attrs << ['Owner', 'Name', 'AttrType', 'Visibility', 'True', 'Value', 'Redefines']
  Observable.types.each do |name, observable|
    unless observable.abstract?
      if observable.parent.abstract? and observable.units and !observable.units.empty?
        attrs << [observable.qn, 'units', "DataTypes::UnitEnum", 'public', 'true', observable.units,
                  "#{observation}::Observation::units"]
      end
      if observable.parent.abstract?
        attrs << [observable.qn, 'type', "DataTypes::DataItemTypeEnum", 'public', 'true', observable.type,
                  "#{observation}::Observation::type"]
      end
      if observable.sub_type
        attrs << [observable.qn, 'subType', "DataTypes::DataItemSubTypeEnum", 'public', 'true',
                  observable.sub_type, "#{observation}::Observation::subType"]
      end
    end
  end
end

CSV.open(File.join($root, 'observation_event_result.csv'), 'w') do |attrs|
  attrs << ['Owner', 'Name', 'AttrType', 'Visibility', 'RedefinesProperty', 'Multiplicity']
  Observable.types.each do |name, observable|
    if observable.enum
      attrs << [observable.qn, 'result', "#{observable.enum.qn}", 'public',
                "#{observation}::Observation::result", '0..1']
    end
  end
end


CSV.open(File.join($root, 'observation_enums.csv'), 'w') do |enums|
  enums << ['Owner', 'Name']
  Enumeration.enums.each do |keys, enum|
    enums << [enum.owner, enum.name]
  end
end

CSV.open(File.join($root, 'observation_enum_values.csv'), 'w') do |enums|
  enums << ['Owner', 'Name', 'OwnerComment']
  Enumeration.enums.each do |keys, enum|
    enum.values.each do |v|
      enums << [enum.qn].concat(v)
    end
  end
end


CSV.open(File.join($root, 'terms.csv'), 'w') do |terms|
  terms << ['Owner', 'Name', 'Descriptionn']
  $parser.terms.sort.each do |g|
    terms << ['Glossary', g.name_property.to_s, g.description]
  end
end

# Find attributes...

owners = {
  'Error' => 'Protocols::MTConnect::MTConnectErrors',
  'Channel' => 'Configuration::SensorConfiguration',
  'Component' => 'Components',
  'Composition' => 'Components::Compositions',
  'DataItem' => 'DataItems',
  'Description' => 'Components',
  'Device' => 'Components',
  'Reference' => 'References',
  'Source' => 'DataItems',
}

CSV.open(File.join($root, 'attribtues.csv'), 'w') do |csv|
  csv << ['Owner', 'Name', 'Description']
  $parser.elements.each do |e|
    if e.has_key?(:attributes)
      e.attributes.to_s.split(',').each do |a|
        attr = $parser[a]
        cls = e.name_property.to_s
        csv << ["#{owners[cls]}::#{cls}", attr.name_property.to_s, attr.description]
      end
    end
  end
end

CSV.open(File.join($root, 'code_values.csv'), 'w') do |types|  
  types << ['Owner', 'Name', 'OwnedComment']
  $parser.models.each do |e|
    if e.has_key?(:code)      
      types << ['AssetModel::CuttingToolModel::CodeEnum', e.code, e.description]
    end
  end  
end


CSV.open(File.join($root, 'measurement_classes.csv'), 'w') do |types|  
  types << ['Owner', 'Name', 'OwnedComment']
  $parser.models.each do |e|
    if e.has_key?(:code)      
      types << ['AssetModel::CuttingToolModel::Measurements', e.name_property.to_s, e.description]
    end
  end  
end

parent = 'AssetModel::CuttingToolModel::Measurements'

CSV.open(File.join($root, 'measurement_codes.csv'), 'w') do |attrs|  
  attrs << ['Owner', 'Name', 'AttrType', 'Visibility', 'True', 'Value', 'Redefines']
  $parser.models.each do |e|
    if e.has_key?(:code)      
      attrs << ["#{parent}::#{e.name_property.to_s}", 'code', "AssetModel::CuttingToolModel::CodeEnum", 'public', 'true', e.code, "#{parent}::Measurement::code"]
                 
    end
  end  
end
