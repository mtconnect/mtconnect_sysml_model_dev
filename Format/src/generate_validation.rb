require 'validation/validations'

class ValidationGenerator
  def initialize(xmi)
    @xmi = xmi
    @skip_models = Set["CSV Imports", #Packages/Models to be skipped while generating definitions
                       "Simulation",  #from the XMI
                       "MTConnect",
                       "Development Process",
                       "Imports"
    ]
  end  
  
  def self.model_class
    ValidationModel
  end

  def generate
    p "generating..."
    
    ValidationModel.generator_class = self
    ValidationModel.skip_models = @skip_models

    Stereotype.collect_stereotypes(@xmi)

    @top = ValidationModel.new(nil, @xmi)
    @top.find_data_types
    @top.find_definitions

    Model.models.each do |k, v|
      # puts "#{k}"
    end

    puts "\n-------------"

    File.open("observation_validations.hpp", "w") do |f|

      f.puts "  Validation ControlledVocabularies {"
      
      events = Model.models.select { |t| t == 'Event Types' }

      types = events["Event Types"].types.map do |type|
        next if type.name.include?('.')

        res = type.relation("result")
        enum = res.final_target.type
        di_type = type.relation('type').default
        
        puts "#{type.name}: #{di_type}"
        text = "    {\"#{type.name}\", {"      
          
        if enum.literals.empty?
          text << "}}"
        else
          e = enum.literals.map do |l|
            s = "{\"#{l.name}\", "
            if l.deprecated
              s << "SCHEMA_VERSION(#{l.deprecated.split('.').join(', ')})"
            else
              s << '0'
            end
            s << '}'
            s
          end
          text << "#{e.join(', ')}}}"
          text
        end
      end.compact.join(",\n")

      f.puts "#{types}\n  };"

    end
  end
end
