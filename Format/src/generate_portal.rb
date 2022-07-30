$: << File.dirname(__FILE__)

require 'json'
require 'portal/mtconnect_html'
require 'portal/portal_model'
require 'portal/helpers'
require 'portal/web_report'

class PortalGenerator

  def initialize(xmi)
    @xmi = xmi
    @skip_models = Set["CSV Imports", #Packages/Models to be skipped while generating definitions
                       "Simulation",  #from the XMI
                       "MTConnect",
                       "Agent Architecture",
                       "Development Process"
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
    
    # Install our logo
    FileUtils.cp(mtconnect, logo)

    # Copy resources
    %w{images app css figures}.each do |loc|
      src = File.expand_path("../#{loc}", File.dirname(__FILE__))
      dest = File.expand_path("#{dir}/#{loc}", File.dirname(__FILE__))

      FileUtils.mkdir_p(dest)
      
      $logger.info "Copying #{src} to #{dest}"
      FileUtils.cp_r(Dir.glob("#{src}/*"), dest)
    end
    
    @doc = WebReport.new(file)
    @doc.update_index(index)    
    @doc.merge_diagrams
    
    PortalModel.generator_class = self
    PortalModel.skip_models = @skip_models

    Stereotype.collect_stereotypes(@xmi)
    
    @top = PortalModel.new(nil, @xmi)
    @top.find_data_types
    @top.find_definitions

    @top.associate_models(@doc)
    PortalModel.generate_enumerations
    PortalModel.generate_stereotypes
    @doc.convert_markdown    
    @doc.deprecate_tree
    
    PortalModel.document_models
    PortalModel.add_characteristics    
    PortalModel.add_constraints
    PortalModel.add_version_to_attributes
    PortalModel.add_inversions
    PortalModel.generate_operations
    PortalModel.generate_children

    vid = "_Version_Folder"
    vn = "Version Additions and Deprecations"

    rows = %w{1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 2.0 2.1}.map do |version|
      [ @top.collect_versioned(version), "Version #{version}" ]
    end.select { |r| r[0] }

    panel = @top.create_panel("Versions", { Version: -1 }, rows.map { |r| [ r[1] ] } )

    @doc.content[vid] = { title: vn, path: vn, html_panel: [], grid_panel: [ panel ], image_panel: [] }
    @doc.struct << { text: vn, qtitle: vid, icon: PackageIcon, expanded: false, leaf: false, children: rows.map { |r| r[0]  } }
    
    @doc.contextualize_search
    
    @doc.write(output)
    @doc.update_resources(resource, res_formatted)
  end

end
