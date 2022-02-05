require 'extensions'

class Operation
  include Extensions

  attr_reader :id, :name, :documentation, :parameters, :pid

  class Parameter
    include Extensions
    
    attr_reader :id, :name, :documentation, :multiplicity, :default, :direction, :type
    
    def initialize(xmi)
      @id = xmi['xmi:id']
      @name = xmi['name']
      @documentation = xmi_documentation(xmi)
      @multiplicity, = get_multiplicity(xmi)
      @direction = xmi['direction']
      @type = xmi['type']

      body = xmi.at('defaultValue/body')
      @default = body.text if body
    end
  end
  
  def initialize(xmi)
    @id = xmi['xmi:id']
    @pid = "Operation__#{@id}"
    @name = xmi['name']
    @documentation = xmi_documentation(xmi)

    @parameters = xmi.xpath('./ownedParameter').map do |par|
      Parameter.new(par)
    end
  end
  
end
