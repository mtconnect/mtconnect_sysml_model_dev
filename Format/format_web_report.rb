require 'kramdown'
require 'fileutils'
require 'json'
require 'fileutils'

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
            "<em>#{args}s</em>"

          when 'block', 'property'
            "<code>#{args}s</code>"

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

def collect_enumerations(doc)
  doc.each do |k, v|
    if k =~ /^Architecture/ and Hash === v and v.include?('title')
      name = v['title']

      data = v.path('grid_panel', 1)
      if data and data.include?('title') and data['title'] == 'Enumeration Literals'
        list = data.path('data_store', 'data')
        if list
          enum = Hash.new
          
          list.each do |e|
            if e['col1'] =~ /title="([^"]+)"/
              entry = $1
              enum[entry] = convert_markdown_to_html(e['col2'])
            end
          end

          Kramdown::Converter::MtcHtml.add_definitions(name, enum)
        end

        list.sort_by! { |e| e['col1'] =~ /title="([^"]+)"/ ? $1 : '' }
      end
    end
  end
end

def convert_markdown(doc)  
  doc.each do |k, v|
    if k =~ /^Architecture/
      docs = v.path('grid_panel', 0, 'data_store', 'data', 1)
      if docs and docs['col0'] =~ /^Documentation/
        docs['col1'] = convert_markdown_to_html(docs['col1'])
      end

      data = v.path('grid_panel', 1)
      if data and data.include?('title')
        title = data['title']
        if title == 'Attributes'
          col = 'col5'
        elsif title == 'Enumeration Literals'
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


if __FILE__ == $PROGRAM_NAME
  index = File.expand_path('../WebReport/index.html', File.dirname(__FILE__))
  file = File.expand_path('../WebReport/data.js', File.dirname(__FILE__))
  output = File.expand_path('../WebReport/data.formatted.js', File.dirname(__FILE__))

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

  content = doc['window.content_data_json']
  
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
