require 'kramdown'
require 'fileutils'
require 'json'
require 'fileutils'
require 'active_support/inflector'
require 'pp'
require 'nokogiri'

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

module Kramdown
  module Parser
    class MTCKramdown < Kramdown

      def initialize(source, options)
        super
        @span_parsers.unshift(:inline_macro)
      end

      INLINE_MACRO_START = /\{\{.*?\}\}/

      # Parse the inline math at the current location.
      def parse_inline_macro
        start_line_number = @src.current_line_number
        @src.pos += @src.matched_size
        # puts "---- #{start_line_number} : #{@src.matched}"
        @tree.children << Element.new(:macro, @src.matched, nil, category: :span, location: start_line_number)
      end
      define_parser(:inline_macro, INLINE_MACRO_START, '{{')
    end
  end

  module Converter
    class MtcHtml < Html
      @@definitions = Hash.new
      
      def self.add_definitions(name, values)
        @@definitions[name] = values
      end

      def self.definitions
        @@definitions
      end
      
      def initialize(root, options)
        super
      end

      def convert_img(el, indent)
        "<blockquote>See <em>#{el.attr['alt']} Diagram</em></blockquote>"
      end
      
      def convert_macro(el, _opts)
        el.value.sub(/\{\{([a-zA-Z0-9_]+)(\(([^\)]+)\))?\}\}/) do |s|
          command = $1
          args = $3.gsub(/\\([<>])/, '\1') if $3
          
          case command         
          when 'term'
            "<em>#{args}</em>"
            
          when 'termplural'
            plural = ActiveSupport::Inflector.pluralize(args)
            "<em>#{plural}</em>"

          when 'block', 'property'
            "<code>#{args}</code>"

          when 'def'
            @@definitions.path(*args.split(':')) || "<code>#{args}</code>"

          when 'latex'
            args

          when 'table'
            "Table #{args}"

          when 'figure'
            "Figure #{args}"

          when "span", "colspan"
            ''

          when "rowspan"
            ''

          when "sect"
            "Section #{args}"

          when "input"
            ''
            
          when 'markdown'
            kd = ::Kramdown::Document.new(args.gsub(/<br\/?>/, "\n"), input: 'MTCKramdown')
            kd.to_mtc_html
            
          else
            args
            
          end
        end
      end
    end
  end
end

Enumerations = Hash.new

def convert_markdown_to_html(content)
  data = content.gsub(%r{<(/)?br[ ]*(/)?>}, "\n").gsub('&gt;', '>')
  kd = ::Kramdown::Document.new(data, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
  kd.to_mtc_html.sub(/^<p>/, '').sub(/<\/p>\n\z/m, '')     
end

def renumber(list)
  list.each_with_index { |e, i| e['col0'].sub!(/^[0-9]+/, (i + 1).to_s) }
end

def deprecate(text)
  "&lt;&lt;deprecated&gt;&gt; #{text}"
end

def convert_markdown(doc)  
  doc.each do |k, v|
    if k =~ /^(Architecture|Glossary|Diagram|Structure)/
      title = v['title']
      deprecated = false

      # Scan the grid panel looking for content
      panels = v['grid_panel']
      panels.each do |panel|
        if panel['hideHeaders'] and panel.path('data_store', 'fields').length == 2
          # Look for documentation
          panel.path('data_store', 'data').each do |row|
            if row['col0'].start_with?('Documentation')
              row['col1'] = convert_markdown_to_html(row['col1'])
              deprecated = row['col1'] =~ /deprecated/i
            end
          end
        else
          desc, = panel['columns'].select { |col| col['text'].start_with?('Documentation') or col['text'].start_with?('Description') }
          name, = panel['columns'].select { |col| col['text'].start_with?('Name') }
          type, = panel['columns'].select { |col| col['text'].start_with?('Type') }

          if desc            
            dc = desc['dataIndex'] if desc
            nc = name['dataIndex'] if name
            tc = type['dataIndex'] if type
            panel.path('data_store', 'data').each do |row|
              if dc and row[dc] != " </br>"
                if nc and row[dc] =~ /deprecated/i
                  row[nc] = deprecate(row[nc])
                end

                row[dc] = convert_markdown_to_html(row[dc])
              end

              if tc and row[tc] =~ /([A-Za-z]+Enum)</ and Enumerations.include?($1)
                row[tc] = format_target(Enumerations[$1], $1, 'icon_177')
              end
            end
          end
        end
      end

      if deprecated
        v['title'] = deprecate(title)
      end
    end
  end
end

def format_name(name, icon)
  "<div title=\"#{name}\" style=\"display: inline !important; white-space: nowrap !important; height: 20px;\">" +
    "<span style=\"vertical-align: middle;\"><img src='images/#{icon}.png' width='16' height='16' title='' style=\"vertical-align: bottom;\">" +
    "</span>#{name}</div></br>"
end

def format_target(id, name, icon)
  "<div title=\"#{name}\" style=\"display: inline !important; white-space: nowrap !important; height: 20px;\">" +
  "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\"><span style=\"vertical-align: middle;\">" +
  "<img src='images/#{icon}.png' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span><a>" +
  "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\">#{name}<a></div>"            
end

def collect_comments(model, name)
  comments = model.xpath("//packagedElement[@name='#{name}' and @xmi:type='uml:Package']")
  recurse = lambda { |ele| [ ele['body'], ele.xpath('./ownedComment').map { |e2| recurse.call(e2) } ] }
  comments.map { |ele| recurse.call(ele) }.flatten.compact.join("\n\n")
end

def document_packages(content, model)
  content.each do |k, v|
    if k =~ /^Package__/
      name = v['title']
      grid = v['grid_panel']
      if grid and grid.empty?
        text = collect_comments(model, name)
        unless text.empty?
          display = format_target(k, name, 'icon_3')
          
          # Check for associations
          grid[0] = { title: "Characteristics ", hideHeaders: true,
                      data_store: { fields: ['col0', 'col1'],
                                    data: [ { col0: 'Name ', col1: display },
                                            { col0: 'Documentation ', col1: convert_markdown_to_html(text) } ] },
                      columns:[ { text: "col0", dataIndex: "col0", flex: 0, width: 192 },
                                { text: "col1", dataIndex: "col1", flex: 1, width: -1 } ],
                      collapsible: false }
        end
      end
    end
  end
end

def generate_enumerations(doc, model)
  package = 'Package__9f1dc926-575b-4c4d-bc3e-f0b64d617dfc'
  
  tree = doc.path('window.navigation_json', 0, 'data')
  loc = tree.index { |e| e['text'] > 'DataTypes' }
  
  list = model.xpath("//packagedElement[@xmi:type='uml:Enumeration']").sort_by { |ele| ele['name'] }.map do |ele|
    { text: ele['name'], qtitle: "Enumeration__#{ele['xmi:id']}", icon: 'images/icon_140.png', expanded: false, leaf: true }
  end

  content = doc['window.content_data_json']
  search = doc['window.search_data_json']
  model.xpath("//packagedElement[@xmi:type='uml:Enumeration']").map do |ele|
    name = ele['name']
    enum = "Enumeration__#{ele['xmi:id']}"
    
    col1 = format_target(enum, name, 'icon_140')
    path = "#{format_target(package, 'DataTypes', 'icon_1')} / #{col1}"
    
    characteristics = { title: 'Characteristics', hideHeaders: true, collapsible: true,
                        data_store: { fields: ['col0', 'col1'], data: [{ col0: 'Name', col1: col1 }] },
                        columns: [ { text: 'col0', dataIndex: 'col0', flex: 0, width: 192 },
                                   { text: 'col1', dataIndex: 'col1', flex: 1, width: -1 } ] }
    
    i = 0
    definitions = Hash.new
    
    rows = ele.xpath('./ownedLiteral[@xmi:type="uml:EnumerationLiteral"]').sort_by { |value| value['name'] }.map do |value|
      i += 1
      vname = value['name']
      lit = format_name(vname, 'icon_69')
      comment, = value.xpath('./ownedComment')
      if comment
        text = convert_markdown_to_html(comment['body'])
        definitions[vname] = text
        if text =~ /deprecated/i
          lit = deprecate(lit)
        end
      end
      
      { col0: "#{i} </br>", col1: lit, col2: text.to_s }
    end
    
    Kramdown::Converter::MtcHtml.add_definitions(name, definitions)
    Enumerations[name] = enum
    
    literals = { title: 'Enumeration Literals', hideHeaders: false, collapsible: true,
                 data_store: { fields: ['col0', 'col1', 'col2'],
                               data: rows },
                 columns: [ { text: '#', dataIndex: 'col0', flex: 0, width: 84 },
                            { text: 'Name', dataIndex: 'col1', flex: 0, width: 300 },
                            { text: 'Documentation', dataIndex: 'col2', flex: 1, width: -1 } ] }
    
    entry = { id: enum, name: "#{name} : <i>Block</i>", type: "block" }
    search['all'] << entry
    search['block'] << entry
    
    [ enum, { title: name, path: path, html_panel: [], grid_panel: [characteristics, literals], image_panel: [] }]
  end.each do |id, value|
    content[id] = value
  end
  
  dt = { text: 'DataTypes', qtitle: package, icon: 'images/icon_1.png',
         children: list, leaf: false, expanded: false }
  tree.insert(loc, dt)
end


if __FILE__ == $PROGRAM_NAME
  dir = ARGV[0] || "../WebReport"

  puts "Working on directory #{dir}"
  
  index = File.expand_path("#{dir}/index.html", File.dirname(__FILE__))
  file = File.expand_path("#{dir}/data.js", File.dirname(__FILE__))
  output = File.expand_path("#{dir}/data.formatted.js", File.dirname(__FILE__))
  logo = File.expand_path("#{dir}/images/logo.png", File.dirname(__FILE__))
  mtconnect = File.expand_path('./MTConnect.png', File.dirname(__FILE__))
  xmi = File.expand_path('../MTConnect SysML Model.xml', File.dirname(__FILE__))
  
  # Reading XMI model
  model = nil
  File.open(xmi) do |xml|
    xmiDoc = Nokogiri::XML(xml).slop!
    model = xmiDoc.at('//uml:Model')
  end

  # Install our logo
  FileUtils.cp(mtconnect, logo)

  text = File.open(index).read
  text.sub!(/src="data\.js"/, 'src="data.formatted.js"')
  File.open(index, 'w') { |f| f.write(text) }
  
  puts "Reading #{file}"
  data = File.read(file)

  data.gsub!(/^\};/, '},')
  data.gsub!(/;$/, ',')

  data.gsub!(/^(window\.[a-z_]+) = '([^']+)'/i, '"\1": "\2"')
  data.gsub!(/^(window\.[a-z_]+) =/i, '"\1": ')

  data.insert(0, '{')
  data.sub!(/,\Z/, "}\n")

  begin
    puts "Parsing #{file}"
    doc = JSON.parse(data)
  rescue
    p $!
  end

  # Add the legal docs to the landing page
  File.open('legal.md') do |f|
    legal = ::Kramdown::Document.new(f.read, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
    panel = doc.path('window.index_page_json', 'html_panel', 0)

    # Clean up the styling
    panel['html'].sub!(%r{margin-top:300px}, 'margin-top:100px')
    panel['html'].sub!(%r{height: 500px}, 'height: 800px')
    # Add the legal content
    panel['html'].
      sub!(%r{</div>}, "<div style=\"text-align: left; margin-left: 50px; margin-right: 50px;\">#{legal.to_mtc_html}</div></div>")
  end

  # Remove the glossary
  # doc['window.navigation_json'].delete_if { |e| e['title'] == 'Glossary' }

  generate_enumerations(doc, model)
  
  content = doc['window.content_data_json']

  puts "Document packages"
  document_packages(content, model)
  
  puts "Converting markdown" 
  convert_markdown(content)

  puts "Writing out #{output}"
  File.open(output, 'w') do |f|
    doc.each do |k, v|
      f.write("#{k} = ");
      f.write(JSON.fast_generate(v, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
      f.write(";\n")
    end
  end
end
