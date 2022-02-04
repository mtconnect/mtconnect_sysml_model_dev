$: << File.dirname(__FILE__)

require 'fileutils'
require 'model'
require 'markdown_type'

class MarkdownModel < Model
  include Document
    
  def self.directory=(dir)
    @@directory = dir
  end

  def self.directory
    @@directory
  end

  def self.type_class
    MarkdownType
  end

  def self.generator_class=(generator_class)
    @@generator = generator_class
  end

  def generator
    @@generator
  end

  def self.generate_md(f, model)
    if @@models[model]
      if model.end_with?('Types') || model == "DataItem Types for Interface"
        @@models[model].types.sort_by! { |t| t.name }
        @@models[model].generate_subtypes(model)
      end
      @@models[model].generate_md(f)
    else
      $logger.fatal "Cannot find model: #{model}"
      exit @@models[model]
    end
  end
  
  def generate_md(f)
    file = "sections/#{short_name}.md"
    f.puts "\n{{input(#{file})}}\n"
    md_directory = File.join(@@directory,"sections")
    FileUtils.mkdir_p(md_directory)
    File.open(File.join(@@directory, file), "w") do |fs|
      $logger.info "Generating model #{@name}"
      fs.puts "\n## #{@name}\n"
      
      generate_documentation(fs)
      @types.each do |type|
        if type.parent.nil? || type.parent.model != self
          recurse_types(fs, type)
        end
      end
    end
  end
  
  def self.generate_glossary(glossary_config)
    FileUtils.mkdir_p(@@directory)
    File.open(File.join(@@directory, "glossary.md"), "w") do |fs|
      glossary_config.each do |glossary_name, glossary_info|
        @@models[glossary_info['model']].types.each do |type|
          if type.parent.nil? || type.parent.model != self
            @@models[glossary_info['model']].recurse_terms(fs, type, glossary_info['type'])
          end
        end
      end
    end
  end

  def self.generate_profile(f, profile_config)
    profile_config.each do |profile_type, profile_info|
        
        f.puts "\n## #{profile_type}\n"
        f.puts "\n![#{profile_type}](figures/#{profile_type.gsub(" ","%20")}.png \"#{profile_type}\")"
        
        @@models[profile_info['model']].types.each do |type|
            if type.type == 'uml:DataType' || type.type == 'uml:Stereotype'
                type.generate_profile_docs(f)
            end
        end
    end
  end

  def self.generate_dataitem_subtypes
    models = ["Sample Types", "Event Types", "Condition Types", "DataItem Types for Interface"]
    list_of_types = []
    
    models.each do |model|
      @@models[model].types.each do |type|
          if type.relation("type")
            list_of_types << type.id
            type_name = type.relation("type").default
            @@generator.dataitemtypes[type_name] = {} unless @@generator.dataitemtypes.include?(type_name)
            @@generator.dataitemtypes[type_name]['subTypes'] = []
          end
        end
    end
    
    models.each do |model|
      @@models[model].types.each do |type|
        type.relations.each do |rel|
          target = rel.final_target.type
              if list_of_types.include?(target.id)
                  @@generator.dataitemtypes[target.relation("type").default]['subTypes'] << "`#{type.relation("subType").default}`"
              end
            end
        end
      end
  end
  
  def generate_subtypes(model)
      list_of_types = []
      @types.each do |type|
        list_of_types << type.id
      end
    
      @types.each do |type|
      if !(type.parent.nil? || type.parent.model != self)
        type.relations.each do |rel|
          if list_of_types.include?(rel.final_target.type.id)
            rel.final_target.type.subtypes << type unless rel.final_target.type.subtypes.include?(type)
            type.is_subtype = true
          end
        end
      end
    end
  end

  def recurse_types(f, type, parent = '')
    parent = parent != '' ? parent : type
    if  (type.type == 'uml:Class' || type.type == 'uml:AssociationClass' || type.type == 'uml:Stereotype' || type.type == 'uml:DataType')
      type.generate_md(f, parent) 
    end

    type.children.each do |t|
      recurse_types(f, t, parent) if t.model == self
    end
  end  
 
  def recurse_terms(f, type, glossary_type)
      type.generate_glossary_docs(f, glossary_type)
  end 
end
