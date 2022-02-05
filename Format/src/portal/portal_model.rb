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
    return if @content.nil? or @name == 'MTConnect'

    if informative
      stereos = "<em>#{informative.html}</em>" 
      name = "#{stereos} #{@name}"
    else
      name = @name
    end
    @content['title'] = name

    $logger.debug "Documenting model: #{name}"
    @tree['text'] = name if @tree

    grid = @content['grid_panel'] if @content
    if grid and grid.empty?
      # Create documentation w/ characteristics section

      chars = [['Name', format_target(@pid, @name, PackageIcon, name)]]
      if @documentation and !@documentation.empty?
        content = "<p>#{convert_markdown_to_html(@documentation)}</p>"
        chars << ['Documentation', content]
      end
      
      grid << gen_characteristics(*chars)

      rows = @types.sort_by { |type| type.name }.map { |type| [ format_obj(type), type.introduced, type.deprecated ] }      
      grid << create_panel('Blocks', { Name: 300, Introduced: 84, Deprecated: 84 }, rows) unless rows.empty?
    end
  end
  
  def self.document_models
    $logger.info "Documenting models"
    @@models.each do |k, m|
      m.document_model
    end
  end

  def generate_enumeration
    $logger.debug "  Generating enumerations for #{@name}"
    @types.sort_by { |t| t.name }.each do |t|
      t.generate_enumeration if t.enumeration?
    end
  end
  
  def self.generate_enumerations
    $logger.info "Generating enumerations types and literals"
    @@models.each do |k, m|
      m.generate_enumeration
    end
  end

  def self.add_characteristics
    $logger.info "Adding characteristics to types"
    @@models.each do |k, m|
      m.types.each { |t| t.add_characteristics }
    end    
  end

  def self.generate_stereotypes
    $logger.info "Generating stereotypes for Profile"

    model = @@models['Stereotypes']
    model.types.each do |t|
      t.generate_stereotype
    end
  end

  def self.add_constraints
    $logger.info "Adding constraints to types"

    @@models.each do |k, m|
      m.types.each { |t| t.add_constraints }
    end    
  end
  
  def self.add_versions_to_relations
    $logger.info "Adding version numbers to properties and relations"
  end

  def self.add_version_to_attributes
    $logger.info "Adding versions to type properties"

    @@models.each do |k, m|
      m.types.each { |t| t.add_version_to_attributes }
    end
  end

  def self.generate_operations
    $logger.info "Adding operations"

    @@models.each do |k, m|
      m.types.each { |t| t.generate_operations }
    end
  end
end
