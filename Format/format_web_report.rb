require 'kramdown'
require 'fileutils'
require 'json'
require 'fileutils'


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
      def self.add_definitions(name, values)
        @@definitions = Hash.new unless defined? @@definitions
        @@definitions[name] = values
      end

      def self.definitions
        @@definitions
      end
      
      def initialize(root, options)
        super
      end
      
      def add_label(label)
        @@labels.add(label)
      end 
      
      def self.reset_labels
        @@labels = Set.new
      end

      def includes_label?(label)
        return @@labels.include?(label)
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
            ent, elem = args.split(':')
            if @@definitions.include?(ent) and @@definitions[ent].include?(elem)
              @@definitions[ent][elem]
            else
              "<code>#{args}</code>"
            end

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

def collect_enumerations(doc, parents = [])
  case doc
  when Array
    doc.each { |child| collect_enumerations(child, parents) }

  when Hash
    doc.each do |k, v|
      if k == 'grid_panel' and v[1] and v[1]['title'] == 'Enumeration Literals'
        if v[0]['data_store']['data'][0]['col1'] =~ /title="([^"]+)"/
          name = $1
          enum = Hash.new

          list = v[1]['data_store']['data']
          list.each do |e|
            if e['col1'] =~ /title="([^"]+)"/
              entry = $1
              enum[entry] = convert_markdown_to_html(e['col2'])
            end
          end
          
          Kramdown::Converter::MtcHtml.add_definitions(name, enum)
        end
      else
        collect_enumerations(v, parents + [k])
      end      
    end
  end
end

def convert_markdown(doc)
  case doc
  when Array
    doc.each { |child| convert_markdown(child) }

  when Hash
    doc.each do |k, v|
      if k =~ /col[1-9]/o and v !~ /^<div/o
        doc[k] = convert_markdown_to_html(v)
      else
        convert_markdown(v)
      end
    end

  else
    # Do nothing
  end
end


if __FILE__ == $PROGRAM_NAME
  file = File.expand_path('../WebReport/data.js', File.dirname(__FILE__))
  orig = File.expand_path('data.orig.js', File.dirname(__FILE__))
  if !File.exist?('data.orig.js')
    FileUtils.copy(file, orig, verbose: true)
  end

  puts "Reading #{orig}"
  data = File.read(orig)

  data.gsub!(/^\};/, '},')
  data.gsub!(/;$/, ',')

  data.gsub!(/^(window\.[a-z_]+) = '([^']+)'/i, '"\1": "\2"')
  data.gsub!(/^(window\.[a-z_]+) =/i, '"\1": ')

  data.insert(0, '{')
  data.sub!(/,\Z/, "}\n")

  begin
    puts "Parsing #{orig}"
    doc = JSON.parse(data)
  rescue
    p $!
  end

  puts "Collecting enumerations"
  collect_enumerations(doc)

  puts "Converting markdown" 
  convert_markdown(doc)

  puts "Writing out #{file}"
  File.open(file, 'w') do |f|
    doc.each do |k, v|
      f.write("#{k} = ");
      f.write(JSON.fast_generate(v, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
      f.write(";\n")
    end
  end
end
