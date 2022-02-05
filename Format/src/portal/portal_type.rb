
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
    @tree = node
    @pid = node['qtitle']
    @content = @doc.content[@pid]

    @@types_by_pid[@pid] = self
  end

  def root_path
    root = @model.path.map { |m| format_obj(PortalModel.model_for_name(m)) }.join(' / ')    
    @path = (@model.path.dup << @name).freeze
    fname = format_obj(self)
    path = "#{root} / #{fname}"
    [fname, path]
  end

  def enumeration_rows
    i = 0
    literals.sort_by { |lit| lit.name }.map.with_index do |lit, i|
      [ i = 1, format_obj(lit), lit.introduced, lit.deprecated, convert_markdown_to_html(lit.description) ]
    end
  end

  def generate_enumeration
    return unless enumeration?

    fname, path = root_path

    characteristics = gen_characteristics(['Name', fname])
    literals = create_panel('Enumeration Literals',
                            { '#': 50, Name: 300, Introduced: 84, Deprecated: 84, Documentation: -1},
                            enumeration_rows)

    add_tree_node(name, path, [characteristics, literals], EnumTypeIcon)
  end

  def generate_stereotype
    return unless @type == 'uml:Stereotype'

    fname, path = root_path
    characteristics = gen_characteristics(['Name', fname],
                                          ['Documentation', convert_markdown_to_html(@documentation)])
    add_tree_node(name, path, [characteristics], BlockIcon)
  end

  def add_characteristics
    if @content
      data = @content.path('grid_panel', 0, 'data_store', 'data')
      if data
        data.unshift({ col0: 'Parent', col1: format_obj(@parent) }) if @parent
        data << { col0: 'Introduced', col1: introduced } if introduced
        data << { col0: 'Deprecated', col1: deprecated } if deprecated
      end
    end
  end

  def add_constraints
    return unless @constraints and !@constraints.empty?

    $logger.debug "Adding constraints to #{@name}"

    rows = @constraints.map do |const|
      [ convert_markdown_to_html(const.documentation), "<code>#{const.ocl}</code>" ]
    end

    # Add to the end of the grid
    @content['grid_panel'] << create_panel('Constraints', { 'Error Message': 400, 'OCL Expression': -1 }, rows)
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
      resize(columns, 'Default Value', 200)

      rows.each do |row|
        html = Nokogiri::HTML(row[ind])
        name, type = html.text.split(':').map { |s| s.strip }

        rel = relation(name)
        if rel
          int = rel.introduced
          dep = rel.deprecated
        end
        row[:int] = int || introduced
        row[:dep] = dep || deprecated
      end      
    end
  end

  def add_tree_node(name, path, panels, icon)
    _, pre = @type.split(':')
    @pid = "#{pre}__#{@id}"
    @doc = @model.doc
    @@types_by_pid[@pid] = self
    
    @content = { title: name, path: path, html_panel: [], grid_panel: panels, image_panel: [] }
    @doc.content[@pid] = @content
    @model.tree['children'] << { text: @name, qtitle: @pid, icon: icon, expanded: false, leaf: true }

    add_entry    
  end

  def generate_operations
    return if @operations.empty?

    @tree['leaf'] = false
    children = @tree['children'] = []
    
    fname, path = root_path        
    @operations.each do |op|
      panels = []
      panels << gen_characteristics(['Name', format_obj(op)],
                                            ['Documentation', convert_markdown_to_html(op.documentation)])

      result = nil
      rows = op.parameters.map.with_index do |par, i|
        type = Type.type_for_id(par.type) || par.type || 'string'

        if par.direction == 'return'
          result = [ format_obj(type), convert_markdown_to_html(par.documentation) ]
          nil
        else
          dflt = par.default ? convert_markdown_to_html("`#{par.default}`") : ''
          [ i, par.name, format_obj(type), par.multiplicity, dflt, convert_markdown_to_html(par.documentation) ]
        end
      end.compact
      panels << create_panel('Parameters', { '#': 50, Name: 200, Type: 150, Multiplicity: 84, 'Default Value': 100, Documentation: -1 }, rows)
      panels << create_panel('Result', { Type: 250, Documentation: -1 }, [result]) if result
      
      content = { title: op.name, path: path, html_panel: [], grid_panel: panels, image_panel: [] }
      @doc.content[op.pid] = content
      children << { text: op.name, qtitle: op.pid, icon: EnumLiteralIcon, expanded: false, leaf: true }

      entry = { id: op.pid, 'name' => "#{op.name} : <i>Opeeration</i>", type: 'operation' }
      @doc.search['all'] << entry
      @doc.search['block'] << entry    
    end

  end
end
