
class Constraint

  attr_reader :id, :name, :ocl, :documentation

  def initialize(rule)
    @id = rule['xmi:id']
    @name = rule['name']
    
    error, = rule.document.root.xpath("//Validation_Profile:validationRule[@base_Constraint='#{@id}']")
    if error
      @documentation = error['errorMessage']
    else
      @documentation = @name
    end

    spec = rule.specification
    @ocl = spec.body.text
  end
end
    
