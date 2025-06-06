require 'model'
require 'portal/portal_type'
require 'portal/helpers'
require 'pp'
require 'portal/portal_diagram'

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

  def self.diagram_class
    PortalDiagram
  end

  @@models_by_pid = Hash.new

  def self.model_for_pid(id)
    @@models_by_pid[id.to_sym]
  end

  def initialize(p, e)
    super
  end

  def associate_content(doc, node, path = [])
    path = (path.dup << node[:text]).freeze
    @doc = doc
    @pid = node[:qtitle].to_sym
    @content = @doc.content[@pid]
    @tree = node

    @tree[:text] = @content[:title] = decorated

    if node.include?(:children)
      node[:children].each do |child|
        if child[:qtitle] =~ /^(Structure|Package|Diagrams)_/
          if child[:qtitle].start_with?('Diagrams_')
            cp = path.dup << "Diagram-#{child[:text]}"
          else
            cp = path.dup << child[:text]
          end
          v = @@model_paths[cp]
          if v
            v.associate_content(doc, child, path)
          else
            $logger.error "Cannot find portal content for #{cp.inspect}"
          end
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
      $logger.debug "Adding Path: #{@path} for #{@name}"
      @types.each do |t|
        if t.type != 'uml:Association'
          pth = @path.dup << t.name
          @@model_paths[pth] = t
        end
      end

      @diagrams.each do |d|
        pth = @path.dup << "Diagram-#{d.name}"
        if @@model_paths.include?(pth)
          puts "!!!!! Duplicate #{pth}"
        else
          @@model_paths[pth] = d
        end
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

    @content = @doc.doc[:'window.index_page_json']
    @pid = nil

    @doc.struct.each do |node|
      model = @@models[node[:text]]
      model.associate_content(@doc, node) if model
    end
  end

  def build_panel(grid, name, list)
    unless list.empty?
      rows = list.select { |e| e.content }.sort_by { |e| e.name }.map do |e|
        [ e.format_target, e.introduced, e.deprecated, e.updated ]
      end
      grid << create_panel(name, { Name: 400, Introduced: 84, Deprecated: 84, Updated: 84 }, rows) unless rows.empty?
    end
  end

  def document_model
    return if @content.nil? or @name == 'MTConnect'

    $logger.debug "Documenting model: #{name}"

    if @content and !@documentation.empty?
      @documentation.sections.each do |section|
        html = "<div style='margin: 1em;'>#{convert_markdown_to_html(section.text)}</div>"
        @content[:html_panel] << { title: section.title, html: html }
      end
    end       

    grid = @content[:grid_panel] if @content
    if grid and grid.empty?
      # Create documentation w/ characteristics section
      grid << gen_characteristics

      build_panel(grid, 'Packages', @children)
      build_panel(grid, 'Blocks', @types)
    end
  end

  def model_path
    return @model_path if defined? @model_path
    @model_path = @path.map { |m| PortalModel.model_for_name(m) }
  end

  def formatted_path
    model_path.map { |m| m.format_target }.join(' / ')
  end
  
  def self.document_models
    $logger.info "Documenting models"
    @@models.each do |k, m|
      m.document_model
      m.diagrams.each  { |d| d.document_diagram }
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

  def self.add_inversions
    $logger.info "Adding inversions to types"

    @@models.each do |k, m|
      m.types.each { |t| t.add_inversions }
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

  def self.generate_children
    $logger.info "Adding Children"

    @@models.each do |k, m|
      m.types.each { |t| t.generate_children_panel }
    end
  end

  

  def collect_versioned(parent, version)
    puts "Collecting changes for #{version}"

    rows = Stereotype.stereotypes(:mtc).map do |id, sts|
      sts.find do |st|
        if st.name == 'normative' or st.name == 'deprecated'
          reason, = [:introduced, :updated, :deprecated, :version].map do |m|
            v = st.send(m) if st.respond_to?(m)
            if v and v.include?(version)
              if m == :version
                case st.name
                when 'normative'
                  'introduced'
                when 'deprecated'
                  'deprecated'
                end
              else
                m.to_s
              end
            end
          end.compact
          if reason
            o = LazyPointer.new(st.id)
            if o.resolve
              break [st, reason.capitalize, o.obj]
            else
              $logger.error "Version resolution: Cannot find object for #{st.id} #{st} #{reason}"
              nil
            end
          end
        end
      end
    end.compact.map do |st, reason, obj|
      row = case obj
            when PortalType
              name = obj.name
              t = case obj.type
                  when 'uml:Stereotype'
                    'Stereotype'

                  when 'uml:Enumeration'
                    'Enumeration'
                    
                  else
                    'Block'
                  end
              [ reason, t, "#{obj.format_target}", obj.pid ]
              
            when Relation::Relation
              owner = obj.owner
              name = owner.name + obj.name
              f = obj.deprecated ? "<strike>#{obj.name}</strike>" : obj.name
              t = Relation::Attribute === obj ? 'Property' : 'Relation'
              [ reason, t, "#{owner.format_target} #{f}", owner.pid ]
              
            when Type::Literal
              owner = obj.owner
              name = owner.name + obj.name
              f = obj.deprecated ? "<strike>#{obj.name}</strike>" : obj.name
              [ reason, 'Literal', "#{owner.format_target} <code>#{f}</code>", owner.pid ]
              
            when Operation
              block = obj.owner
              name = block.name + obj.name
              [ reason, 'Operation', "#{block.format_target} #{obj.format_target}", block.pid ]
              
            when Operation::Parameter
              owner = obj.owner
              block = owner.owner
              name = block.name + owner.name + obj.name
              f = obj.deprecated ? "<strike>#{obj.name}</strike>" : obj.name
              [ reason, 'Parameter', "#{block.format_target} #{owner.format_target}(#{f})", block.pid ]
              
            else
              $logger.warn "Cannot find info for #{obj.class} #{obj.name}"
              nil
            end
      if row
        if row[0] == 'Updated' and version > '2.0'and prior = prior_version(version)
          row[0] = "Updated (Previous: #{format_version_link(prior, prior, prior, row.last)})"
        end
        [name, row[0...-1] ]
      end
    end.compact.sort_by { |name, row| name }.map.with_index { |v, i| v[1].unshift(i + 1) }

    n = "Version #{version}"
    l = version < $mtconnect_version ? format_version_link(version, version, n, "_Version_#{version}") : n
    panel = create_panel("#{n} Entities", { '#': 64, Change: 180, Type: 90, Entity: -1 }, rows)

    vid = "_Version_#{version}"
    vc = { title: l, path: "#{parent} / #{ format_name_html(n, PackageIcon) }", html_panel: [], grid_panel: [ panel ], image_panel: [] }
    @doc.content[vid] = vc
    { text: n, qtitle: vid, icon: PackageIcon, expanded: false, leaf: true }
  end
end
