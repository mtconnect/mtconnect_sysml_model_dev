$: << File.dirname(__FILE__)

require 'json'
require 'portal/mtconnect_html'
require 'portal/portal_model'
require 'portal/helpers'
require 'portal/web_report'

# Icon constants here
EnumTypeIcon = 'images/enum_type_icon.png'.freeze
EnumLiteralIcon = 'images/enum_literal_icon.png'.freeze
PackageIcon = 'images/package_icon.png'.freeze
BlockIcon = 'images/block_class_icon.png'.freeze
  
class Hash
  def path(*args)
    o = self
    args.each do |v|
      if Hash === o or (Array === o and Integer === v)
        o = o[v]
      else
        return nil
      end
      
      return nil if o.nil?
    end

    return o
  end
end

class PortalGenerator

  def initialize(xmi)
    @xmi = xmi
    @skip_models = Set["CSV Imports", #Packages/Models to be skipped while generating definitions
                       "Simulation",  #from the XMI
                       "MTConnect",
                       "Agent Architecture",
                       "Development Process",
                       "Examples"
    ]
  end

  def self.model_class
    PortalModel
  end

  def generate
    dir = File.join('..', '..', 'WebReport')
    
    $logger.info "Working on directory #{dir}"
    
    index = File.expand_path("#{dir}/index.html", File.dirname(__FILE__))
    file = File.expand_path("#{dir}/data.js", File.dirname(__FILE__))
    resource = File.expand_path("#{dir}/resource.js", File.dirname(__FILE__))
    res_formatted = File.expand_path("#{dir}/resource.formatted.js", File.dirname(__FILE__))
    output = File.expand_path("#{dir}/data.formatted.js", File.dirname(__FILE__))
    logo = File.expand_path("#{dir}/images/logo.png", File.dirname(__FILE__))
    mtconnect = File.expand_path('../MTConnect.png', File.dirname(__FILE__))
    src_images = File.expand_path('../images', File.dirname(__FILE__))
    dest_images = File.expand_path("#{dir}/images", File.dirname(__FILE__))
    
    # Install our logo
    FileUtils.cp(mtconnect, logo)
    
    $logger.info "Copying images to #{dest_images}"
    FileUtils.cp_r(Dir.glob("#{src_images}/*"), dest_images)

    
    @doc = WebReport.new(file)
    @doc.update_index(index)
    @doc.merge_diagrams
    
    PortalModel.generator_class = self
    PortalModel.skip_models = @skip_models
    @top = PortalModel.new(@xmi)
    @top.find_data_types
    @top.find_definitions

    @top.associate_models(@doc)
    @doc.convert_markdown
    @doc.deprecate_tree
    
    @top.document_models

    @doc.write(output)
    @doc.update_resources(resource, res_formatted)
  end

end
