
require 'type'
require 'portal/helpers'

class Type::Literal
  include PortalHelpers
end

class PortalType < Type
  include Document
  include PortalHelpers

  attr_reader :path, :pid, :content

  @@types_by_pid = Hash.new


  def self.type_for_pid(id)
    @@types_by_pid[id]
  end

  def initialize(model, e)
    super

    lits = literals
    unless lits.empty?
      definitions = Hash.new
      lits.sort_by { |lit| lit.name }.each do |lit|
        definitions[lit.name] = convert_markdown_to_html(lit.description)
      end

      Kramdown::Converter::MtcHtml.add_definitions(@name, definitions)
    end
  end
  
  def associate_content(doc, node, path)
    @path = (path.dup << node['text']).freeze
    @doc = doc
    @pid = node['qtitle']
    @content = @doc.content[@pid]

    @@types_by_pid[@pid] = self
  end

  def enumeration_rows
    i = 0
    literals.sort_by { |lit| lit.name }.map do |lit|
      i += 1

      name = format_obj(lit)
      { col0: "#{i} </br>",
        col1: name,
        ver: lit.introduced.to_s,
        dep: lit.deprecated.to_s,
        col2: convert_markdown_to_html(lit.description) }
    end
  end

  def root_path
    root = @model.path.map { |m| format_obj(PortalModel.model_for_name(m)) }.join(' / ')    
    @path = (@model.path.dup << @name).freeze
    fname = format_obj(self)
    path = "#{root} / #{fname}"
    [fname, path]
  end

  def generate_enumeration
    return unless enumeration?

    fname, path = root_path
    @pid = "Enumeration__#{id}"
    @doc = @model.doc
    @@types_by_pid[@pid] = self

    characteristics = gen_characteristics(['Name', fname])

    # Create the grid of literals
    literals = { title: 'Enumeration Literals', hideHeaders: false, collapsible: true,
                 data_store: { fields: ['col0', 'col1', 'ver', 'dep', 'col2'], data: enumeration_rows },
                 columns: [ { text: '# ', dataIndex: 'col0', flex: 0, width: 84 },
                            { text: 'Name ', dataIndex: 'col1', flex: 0, width: 300 },
                            { text: 'Introduced', dataIndex: 'ver', flex: 0, width: 84 },
                            { text: 'Deprecated', dataIndex: 'dep', flex: 0, width: 84 },
                            { text: 'Documentation ', dataIndex: 'col2', flex: 1, width: -1 } ] }
    
    # Add the items to the search
    @content = { title: name, path: path, html_panel: [], grid_panel: [characteristics, literals], image_panel: [] }
    @doc.content[@pid] = @content
    @model.tree['children'] << { text: @name, qtitle: @pid, icon: EnumTypeIcon, expanded: false, leaf: true }

    add_entry
  end

  def generate_stereotype
    return unless @type == 'uml:Stereotype'

    fname, path = root_path
    @pid = "Stereotype__#{id}"
    @doc = @model.doc
    @@types_by_pid[@pid] = self

    characteristics = gen_characteristics(['Name', fname],
                                          ['Documentation', convert_markdown_to_html(@documentation)])

    # Add the items to the search
    @content = { title: name, path: path, html_panel: [], grid_panel: [characteristics], image_panel: [] }
    @doc.content[@pid] = @content
    @model.tree['children'] << { text: @name, qtitle: @pid, icon: BlockIcon, expanded: false, leaf: true }

    add_entry
  end

  def add_characteristics
    if @content
      characteristics, = @content['grid_panel']
      if characteristics
        data = characteristics.path('data_store', 'data')
        if @parent
          data.unshift({ col0: 'Parent', col1: format_obj(@parent) })
        end
        if v = introduced
          data << { col0: 'Introduced', col1: v }
        end
        if v = deprecated
          data << { col0: 'Deprecated', col1: v }
        end
      end
    end
  end

  def add_constraints
    return unless @constraints and !@constraints.empty?

    $logger.debug "Adding constraints to #{@name}"

    rows = @constraints.map do |const|
      { col0: convert_markdown_to_html(const.documentation), col1: "<code>#{const.ocl}</code>" }
    end
    
    constraints = { title: 'Constraints', hideHeaders: false, collapsible: true,
                    data_store: { fields: ['col0', 'col1'], data: rows },
                    columns: [ { text: 'Error Message', dataIndex: 'col0', flex: 0, width: 600 },
                               { text: 'OCL Expression ', dataIndex: 'col1', flex: 1, width: -1 }] }
    # Add to the end of the grid
    @content['grid_panel'] << constraints
  end

  def add_version_to_attributes
    return if @content.nil? or !@content.include?('grid_panel')
    
    $logger.debug "Adding version to #{@name}"

    grid = @content['grid_panel']
    grid.each do |panel|
      next if panel['title'].nil? or panel['title'].start_with?('Characteristics')

      rows = panel.path('data_store', 'data')

      columns = panel['columns']
      nc = columns.detect { |col| col['text'].start_with?('Name') }
      next unless nc and nc.include?('dataIndex')

      ind = nc['dataIndex']
      fields = panel.path('data_store', 'fields')
      pos = fields.index(ind) + 1
      fields.insert(pos, :int, :dep)
      columns.insert(pos,
                     { text: "Int", dataIndex: 'int', flex: 0, width: 64 },
                     { text: "Dep", dataIndex: 'dep', flex: 0, width: 64 })

      resize(columns, 'Type', 150)
      resize(columns, 'Multiplicity', 100)
      resize(columns, 'Default Value', 100)

      rows.each do |row|
        html = Nokogiri::HTML(row[ind])
        name, type = html.text.split(':').map { |s| s.strip }

        rel = relation(name)
        if rel
          int = rel.introduced
          dep = rel.deprecated
        end
        int ||= introduced
        dep ||= deprecated

        row[:int] = int
        row[:dep] = dep
      end
      
    end
  end
end
