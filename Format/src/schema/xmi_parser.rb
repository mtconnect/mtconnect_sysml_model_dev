
class XMIParser
  attr_reader :types, :subtypes, :statistics, :units, :native_units, :coordinate_systems_attr, :reset_triggers, :representations,
             :filters, :compositions, :components, :samples, :events, :terms
  
  def initialize
    File.open(File.join(File.dirname(__FILE__), '..', '..', 'MTConnect SysML Model.xml')) do |xmi|
        xmiDoc = Nokogiri::XML(xmi).slop!
        @model = xmiDoc.at('//uml:Model')
    end
    generate_all()
  end

  def generate_all
  
    @terms = generate_definitions()
  
    @types = generate_enum('SampleEnum','EventEnum','ConditionEnum')
    @subtypes = generate_enum('DataItemSubTypeEnum')
    @statistics = generate_enum('StatisticEnum')
    @units = generate_enum('UnitEnum')
    @native_units = generate_enum('NativeUnitEnum')
    @coordinate_systems_attr = generate_enum('CoordinateSystemEnum')
    @reset_triggers = generate_enum('ResetTriggerEnum')
    @representations = generate_enum('RepresentationEnum')
    @filters = generate_enum('FilterEnum')
    @compositions = generate_enum('CompositionTypeEnum')
    
    @components = generate_element_types('Components', 'Component', 'Component Types')
    @components = @components.merge(generate_element_types('Components', 'Component', 'Devices'))
    @samples = generate_element_types('Observations', 'Sample', 'Sample Types')
    @events = generate_element_types('Observations', 'Event', 'Event Types')
  end
  
  def generate_definitions
    terms = Hash.new
    terms_xmi_list = @model.xpath('//ownedComment')
    terms_xmi_list.each do |term|
      if term.parent.name != 'ownedComment'
        terms[term.parent['name']] = term['body']
      end
    end
    return terms
  end

  def generate_enum(*args)
    enumeration_attr = Hash.new
    args.each do |arg|
      enum_element = @model.at("//*[@name='"+arg+"']")
      enum_literals = enum_element.xpath('./ownedLiteral')
      enum_literals.each do |literal|
        name = literal['name']
        enumeration_attr[name] = Hash.new
        enumeration_attr[name]['name'] = name
        enumeration_attr[name]['description'] = literal.at("./ownedComment")['body']
      end
    end
    return enumeration_attr
  end

  def generate_element_types(package, element_name, types_package)
    element_attr = Hash.new
    element_type_ids = Hash.new

    package = @model.at("//*[@xmi:type='uml:Package' and @name='"+package+"']")
    element_xmi = package.at("[@name='"+element_name+"']")
    element_type_ids[element_xmi["xmi:id"]] = element_name
    
    element_types_package = package.at("[@name='"+types_package+"']")
    
    element_types_package.children.each do |element|
      next unless element["xmi:type"] == "uml:Class" or element["xmi:type"] == "uml:AssociationClass"
      next if element["xmi:type"] == "uml:Class" and types_package == "Devices"
      name = element['name']
      description = element.at("./ownedComment") ? element.at("./ownedComment")['body'] : ""
      parent_id = element.at("./generalization") ? element.at("./generalization")['general'] : ""
      units = get_units(element)
      facet, enums = get_facet(element)
      
      element_type_ids[element['xmi:id']] = name
      element_attr[name] = Hash.new
      element_attr[name]['name'] = name
      element_attr[name]['description'] = description
      element_attr[name]['parent'] = parent_id
      element_attr[name]['units'] = units
      element_attr[name]['facet'] = facet
      element_attr[name]['enums'] = enums
    end
    
    element_attr.each do |name, element|
      if types_package == "Devices"
        element_attr[name]['parent'] = "Component"
        next
      end
      element_attr[name]['parent'] = element_type_ids[element['parent']]
    end
    
    return element_attr
  end
  
  def get_units(element)
    units = element.at("[@name='units']") ? element.at("[@name='units']").at("./defaultValue")['value'] : ""
    if not units and element.at("[@name='units']").at("./defaultValue")
      units_id = element.at("[@name='units']").at("./defaultValue")['instance']
      units = @model.at("//*[@xmi:id='"+units_id+"']")['name']
    end
    return units
  end
  
  def get_facet(element)
    facet = "string"
    enums = ""
    facet_xmi_id = element.at("[@name='result']") ? element.at("[@name='result']")['type'] : ""
    if facet_xmi_id and facet_xmi_id != ""
      facet_xmi_element = @model.at("//*[@xmi:id='"+facet_xmi_id+"']")
      facet_xmi_type = facet_xmi_element['xmi:type']
      if facet_xmi_type == 'uml:Enumeration'
        facet = 'enumeration'
        enums = generate_enum(facet_xmi_element['name'])
      elsif facet_xmi_type == 'uml:DataType'
        facet = facet_xmi_element['name'].downcase
      end
    end
    return facet, enums
  end

end