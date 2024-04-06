$: << File.dirname(__FILE__)

require 'json'
require 'portal/mtconnect_html'
require 'portal/portal_model'
require 'portal/helpers'
require 'portal/web_report'

class ValidationModel < Model
  def self.generator_class=(generator_class)
    @@generator = generator_class
  end

  def generator
    @@generator
  end

  def self.type_class
    ValidationType
  end
  def self.diagram_class
    ValidationDiagram
  end
end

class ValidationType < Type
  
end

class ValidationDiagram < Diagram
end
