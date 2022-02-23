require 'logger'
require 'extensions'

class Diagram
  include Extensions

  attr_reader :model, :name, :xmi, :id, :type, :stereotypes, :documentation

  def initialize(model, e)
    @model = model
    @xmi = e
    @id = e['xmi:id']

    @name = e['name']
    
    @documentation = xmi_documentation(e) || ''
    @stereotypes = xmi_stereotype(e)

    @type = e['xmi:type']       
    $logger.debug "  -- Creating diagram #{@stereotypes} #{@name} : #{@type}"    
  end
end
