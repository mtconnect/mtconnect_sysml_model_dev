$: << File.dirname(__FILE__)

require "json"
require "markdown/markdown_model"
require "markdown/markdown_merger"
require "markdown/documents"
require "latex/latexify"

class DocumentGenerator
  include Document
  include CommonDocument
  include Kramdown::Converter

  attr_reader :skip_models, :part_num, :part_config, :profile, :xmi
  attr_accessor :enums, :dataitemtypes 

  def initialize(xmi)
    @xmi = xmi
    @skip_models = Set["CSV Imports",    #Packages/Models to be skipped while generating definitions
      "Simulation",                       #from the XMI
      "MTConnect",
      "Agent Architecture",
      "Development Process",
      "Examples"
    ]
    @enums = ["DataItemTypeEnum",        #Enumerations to be ignored during recursive gen of docs
      "SampleEnum",
      "EventEnum",
      "ConditionEnum",
      "DataItemSubTypeEnum",              #These enums have specific formats defined in markdown_type.rb
      "CompositionTypeEnum",
      "CodeEnum"
    ] 
    @dataitemtypes = $dataitemtypes            #DataItem types for use in multiple Parts docs
  end

  def generate_all
    find_model_definitions()
    generate_documentation()
  end

  def find_model_definitions
    self.class.model_class.generator_class = self
    self.class.model_class.skip_models = @skip_models
    self.class.model_class.new(@xmi).find_definitions
    self.class.model_class.generate_dataitem_subtypes
  end

  def self.model_class
    MarkdownModel
  end

  def parse_config
    config_file = File.join(File.dirname(__FILE__),"..","config","document_structure.json")
    unless File.exist?(config_file)
      $logger.error "Documentation Config file not found."
      exit
    end
    doc_outlines = File.read(config_file)
    return JSON.parse(doc_outlines)
  end

  def generate_documentation
    doc_outlines = parse_config()
    doc_outlines["documents"].each do |part_num, part_config|
      @part_num = part_num
      @part_config = part_config
      @profile = doc_outlines["profile"]
      directory_name = @part_config["directory"]
      directory_path = File.join(File.dirname(__FILE__),"..","markdown_documentation",directory_name)
      
      self.class.model_class.directory = directory_path
      self.class.model_class.generate_glossary(doc_outlines["glossary"])

      generate_common_docs(
        root_model = @xmi,
        doc_num = @part_num,
        doc_title = @part_config["doc_title"],
        version_num = $mtconnect_version,
        part_dir = directory_name
      )
      generate_sections()
      generate_profile()  
      flatten_md()
      convert_to_latex()
    end
  end

  def generate_profile
    $logger.info "Generating MTConnect Profile"
    profile_file = File.join(self.class.model_class.directory, "profile.md")
    File.open(profile_file, "w") do |f|
      generate_section_intro(
        f = f,
        root_model = @xmi,
        section_package_name = "Supporting Documents",
        section_name = "MTConnect Profile"
        )
      self.class.model_class.generate_profile(f, @profile)
    end
  end

  def generate_sections
    directory_name = @part_config["directory"]
    main_file = File.join(self.class.model_class.directory,directory_name+".md")
    File.open(main_file,"w") do |f|
      @part_config["models"].each do |model|
        case model.class.to_s
        when "String"
          generate_section_intro(
            f = f,
            root_model = @xmi,
            section_package_name = "Supporting Documents",
            section_name = model
          )
        when "Hash"
          section_name = model.keys[0]
          generate_section_intro(
            f = f,
            root_model = @xmi,
            section_package_name = model[section_name][0],
            section_name = section_name
          )
          $logger.info "\nGenerating Documents for #{section_name}"
          model[section_name].each do |mod|
            self.class.model_class.generate_md(f, mod)
          end
        else
          $logger.error "Invalid model data type #{model.class}"
        end
      end
    end
  end

  def flatten_md
    $logger.info "Generating flattened MD for #{@part_config["directory"]}"
    MarkdownMerger.flatten(self.class.model_class)
  end

  def convert_to_latex
    $logger.info "Generating LaTeX documentation for #{@part_config["directory"]}"
    #Generate LaTeX file for each MD file excluding main.md and main_flattened.md
    #LaTeX main file and document class are defined in the model itself. 
    (Dir[File.join(self.class.model_class.directory,"*.md")]|
        Dir[File.join(self.class.model_class.directory, "sections","*.md")]).each do |file|
      MarkdownConverter.generate_latex(file) if !["main.md", "main_flattened.md"].include?(File.basename(file))
    end
    MtcLatex.reset_labels()
  end
end
