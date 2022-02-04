require 'model'
require 'portal/portal_type'
require 'portal/helpers'
require 'pp'

class PortalModel < Model
  include Document
  include PortalHelpers

  attr_reader :pid, :content, :doc, :path, :tree
  
  def self.generator_class=(generator_class)
    @@generator = generator_class
  end

  def generator
    @@generator
  end

  def self.type_class
    PortalType
  end

  @@models_by_pid = Hash.new

  def self.model_for_pid(id)
    @@models_by_pid[id]
  end

  def initialize(e)
    super
  end

  def associate_content(doc, node, path = [])
    path = (path.dup << node['text']).freeze
    @doc = doc
    @pid = node['qtitle']
    @content = @doc.content[@pid]
    @tree = node

    if node.include?('children')
      node['children'].each do |child|
        if child['qtitle'] =~ /^(Structure|Package)_/
          cp = path.dup << child['text']
          v = @@model_paths[cp]
          v.associate_content(doc, child, path)
        end
      end
    end

    @@models_by_pid[@pid] = self
  end

  def xmi_path(node)
    node.ancestors.reverse.map { |a| a['name'] }.compact[1..-1] || []
  end
  
  def cache_path
    if @name != 'MTConnect'
      @path = xmi_path(@xmi) << @name
      @@model_paths[@path] = self
      @types.each do |t|
        pth = @path.dup << t.name
        @@model_paths[pth] = t
      end
    end
  end

  def associate_models(doc)
    @doc = doc
    @doc.add_license(@documentation)
    @@model_paths = Hash.new

    @@models.each do |k, m|
      m.cache_path
    end

    @content = @doc.doc['window.index_page_json']
    @pid = nil

    @doc.struct.each do |node|
      model = @@models[node['text']]
      model.associate_content(@doc, node) if model
    end
  end

  def document_model
    return unless @content
    
    if @stereotypes
      @content['title'] = "#{@stereotypes} #{@name}"
    end

    grid = @content['grid_panel'] if @content
    if grid and grid.empty? and !@documentation.empty?
      # Create documentation w/ characteristics section
      content = "<p>#{convert_markdown_to_html(@documentation)}</p>"
      
      grid << gen_characteristics(['Name', format_target(@pid, @name, PackageIcon)],
                                  ['Documentation', content])      
      
      rows = @types.map do |type|
        dep = type.deprecated
        { name: format_obj(type), introduced: type.introduced.to_s, deprecated: dep.to_s }
      end
      
      blocks = { title: 'Blocks', hideHeaders: false, collapsible: true,
                 data_store: { fields: ['name', 'introduced', 'deprecated'], data: rows },
                 columns: [ { text: 'Name ', dataIndex: 'name', flex: 0, width: 300 },
                            { text: 'Introduced', dataIndex: 'introduced', flex: 0, width: 84 },
                            { text: 'Deprecated', dataIndex: 'deprecated', flex: 0, width: 84 } ] }

      grid << blocks
    end
  end
  
  def self.document_models
    @@models.each do |k, m|
      m.document_model
    end
  end

  def generate_enumeration
    @types.sort_by { |t| t.name }.each do |t|
      t.generate_enumeration if t.enumeration?
    end
  end
  
  def self.generate_enumerations
    @@models.each do |k, m|
      m.generate_enumeration
    end
  end

  def self.add_characteristics
    @@models.each do |k, m|
      m.types.each { |t| t.add_characteristics }
    end    
  end
end
