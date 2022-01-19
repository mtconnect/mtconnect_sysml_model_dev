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

def convert_markdown_to_html(content)
  data = content.gsub(%r{<(/)?br[ ]*(/)?>}, "\n").gsub('&gt;', '>')
  kd = ::Kramdown::Document.new(data, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
  kd.to_mtc_html.sub(/^<p>/, '').sub(/<\/p>\n\z/m, '')     
end

def renumber(list)
  list.each_with_index { |e, i| e['col0'].sub!(/^[0-9]+/, (i + 1).to_s) }
end

def collect_enumerations(doc)
  doc.each do |k, v|
    if k =~ /^Architecture/ and Hash === v and v.include?('title')
      name = v['title']

      # Get the interesting pieces of the doc and skip entry if they don't exist
      data = v.path('grid_panel', 1)
      next unless data
      title = data['title']
      next unless title
      list = data.path('data_store', 'data')
      next unless list
      
      if title == 'Enumeration Literals'
        enum = Hash.new

        # Same the converted docs for each entry in the enums
        list.each do |e|
          if e['col1'] =~ /title="([^"]+)"/
            entry = $1
            enum[entry] = convert_markdown_to_html(e['col2'])
          end
        end
        
        Kramdown::Converter::MtcHtml.add_definitions(name, enum)
        list.sort_by! { |e| e['col1'] =~ /title="([^"]+)"/ ? $1 : '' }
        renumber(list)

      elsif title == 'Attributes'
        attributes = Hash.new { |h, k| h[k] = [] }
        
        list.each_with_index do |e, i|
          # Check if the icon is icon_1 (the bullet icon). These are relationships and should remain
          # Otherwise, if it is named property, remove dups
          match = /title="([^"]+)".+?img[ ]+src='([^']+)'?/.match(e['col1'])
          if match
            prop, type = match[1].split(/[ ]*:[ ]*/)
            icon = match[2]            
            attributes[prop] << e unless prop.empty? or icon =~ /icon_1\.png/
          end
        end

        # Cleanup and remove the dups
        attributes.each do |k, v|
          if v.length > 1
            # Preserve the last one
            last = v.pop
            # Check if there are docs for the final value, if so keep them
            if last['col5'] =~ %r{^[ ]*</br>$}
              # Otherwise, find the last set of docs and replace the current docs
              docs = v.map { |e| e['col5'] if e['col5'] !~ %r{^[ ]*</br>$} }.compact.last
              last['col5'] = docs if docs
            end

            # Remove the other entries.
            v.each do |e|
              list.delete_if { |i| i['col0'] == e['col0'] }
            end
          end
        end

        renumber(list)
      end
    end
  end
end

def convert_markdown(doc)  
  doc.each do |k, v|
    if k =~ /^(Architecture|Glossary|Diagram)/
      type = $1
      title = v['title']
      
      docs = v.path('grid_panel', 0, 'data_store', 'data', 1)
      if docs and docs['col0'] =~ /^Documentation/
        docs['col1'] = convert_markdown_to_html(docs['col1'])
      end

      if type == 'Glossary' or type == 'Diagram'
        data = v.path('grid_panel', 0)
      else
        data = v.path('grid_panel', 1)
      end
      if data and data.include?('title')
        if type != 'Diagram'
          title = data['title']
        end
        
        if title == 'Attributes'
          col = 'col5'
        elsif type == 'Glossary' and title =~ /Characteristics/
          col = 'col1'
        elsif title == 'Enumeration Literals' or type == 'Glossary' or (type == 'Diagram' and title =~ /Glossary/)
          col = 'col2'
        end
        
        if col
          list = data.path('data_store', 'data')
          list.each do |row|
            if row.include?(col) and row[col] !~ /^[ ]*</
              row[col] = convert_markdown_to_html(row[col])
            end
          end
        end
      end
    end
  end
end

def document_packages(content, model)
  content.each do |k, v|
    if k =~ /^Package__/
      name = v['title']
      grid = v['grid_panel']
      if grid and grid.empty?        
        comment = lambda do |ele|
          [ ele['body'], ele.xpath('./ownedComment').map { |e2| comment.call(e2) } ]
        end
        comments = model.xpath("//packagedElement[@name='#{name}']")
        text = comments.map do |ele|
          comment.call(ele)
        end.flatten.compact.join("\n\n")

        unless text.empty?
          display = "<div title=\"#{name}\" style=\"display: inline !important; white-space: nowrap !important; height: 20px;\">" +
                    "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{k}');return false;\"><span style=\"vertical-align: middle;\">" +
                    "<img src='images/icon_3.png' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span><a>" +
                    "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{k}');return false;\">#{name}<a></div>"
          
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


if __FILE__ == $PROGRAM_NAME
  index = File.expand_path('../WebReport/index.html', File.dirname(__FILE__))
  file = File.expand_path('../WebReport/data.js', File.dirname(__FILE__))
  output = File.expand_path('../WebReport/data.formatted.js', File.dirname(__FILE__))
  logo = File.expand_path('../WebReport/images/logo.png', File.dirname(__FILE__))
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
  doc['window.navigation_json'].delete_if { |e| e['title'] == 'Glossary' }
  
  content = doc['window.content_data_json']

  puts "Document packages"
  document_packages(content, model)
  
  puts "Collecting enumerations"
  collect_enumerations(content)

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
