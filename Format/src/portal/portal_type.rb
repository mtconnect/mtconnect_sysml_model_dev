
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

  def generate_enumeration
    return unless enumeration?

    root = @model.path.map { |m| format_obj(PortalModel.model_for_name(m)) }.join(' / ')    
    @path = (@model.path.dup << @name).freeze

    fname = format_obj(self)

    path = "#{root} / #{fname}"
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
end
