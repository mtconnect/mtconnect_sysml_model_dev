require 'extensions'

class Operation
  include Extensions

  attr_reader :id, :name, :documentation, :parameters, :pid, :stereotypes, :owner

  class Parameter
    include Extensions
    
    attr_reader :id, :name, :documentation, :multiplicity, :default, :direction, :type, :stereotypes, :owner
    
    def initialize(owner, xmi)
      @owner = owner
      @id = xmi['xmi:id']
      @name = xmi['name']
      @documentation = xmi_documentation(xmi)
      @multiplicity, = get_multiplicity(xmi)
      @direction = xmi['direction']
      @type = xmi['type']
      @stereotypes = xmi_stereotype(xmi)

      body = xmi.at('defaultValue/body')
      @default = body.text if body

      LazyPointer.register(@id, self)
    end
  end
  
  def initialize(owner, xmi)
    @owner = owner
    @id = xmi['xmi:id']
    @pid = "Operation__#{@id}"
    @name = xmi['name']
    @documentation = xmi_documentation(xmi)
    @stereotypes = xmi_stereotype(xmi)

    @parameters = xmi.xpath('./ownedParameter').map do |par|
      Parameter.new(self, par)
    end
    
    LazyPointer.register(@id, self)
  end
  
end
