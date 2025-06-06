require 'portal/helpers'
require 'active_support/inflector'

module Kramdown
  module Parser
    class MtcHtmlKramdown < Kramdown

      def initialize(source, options)
        super
        @span_parsers.unshift(:html_inline_macro)
      end

      INLINE_MACRO_START = /\{\{.*?\}\}/

      # Parse the inline math at the current location.
      def parse_inline_macro
        start_line_number = @src.current_line_number
        @src.pos += @src.matched_size
        # puts "---- #{start_line_number} : #{@src.matched}"
        @tree.children << Element.new(:macro, @src.matched, nil, category: :span, location: start_line_number)
      end
      define_parser(:html_inline_macro, INLINE_MACRO_START, '{{')
    end
  end

  module Converter
    class MtcHtml < Html
      include PortalHelpers
      
      @@definitions = Hash.new

      def self.add_definitions(name, values)
        @@definitions[name] = values
      end

      def self.definitions
        @@definitions
      end
      
      def initialize(root, options)
        @figure_num = 0
        @figure_nums = Hash.new { |h, k| h[k] = (@figure_num += 1) }

        @table_num = 0
        @table_nums = Hash.new { |h, k| h[k] = (@table_num += 1) }
        super
      end

      def convert_img(el, indent)
        num = @figure_nums[el.attr['title']]
        # puts "Image #{el.attr['title']} = #{num}"

        el.attr['style'] = "max-width: #{(el.attr['width'].to_f * 100.0).to_i}%;"
        el.attr.delete('width');
        caption = el.attr['alt'] || el.attr['title']
        %{<p style="width=100vw; text-align: center">#{super}<br/><em>Figure #{num}: #{caption}</em></p>}
      end

      def convert_table(el, indent)
        num = @table_nums[el.attr['label']]
        # puts "Table #{el.attr['title']} = #{num}"

        el.attr['class'] = 'doctable'
        caption = el.attr['caption'] || el.attr['title']
        %{<div style="display: flex; align-items: center; justify-content: center;">#{super}</div>\
          <p style="text-align: center; margin-top: 5px;"><em>Table #{num}: #{caption}</em></p>}
      end

      def convert_macro(el, _opts)
        if el.value =~ /\{\{([a-zA-Z0-9_]+)(\(([^\)]+)\))?\}\}/
          command = $1
          args = $3.gsub(/\\([<>])/, '\1') if $3
          
          case command         
          when 'term'
            format_term(args)
            
          when 'termplural'
            plural = ActiveSupport::Inflector.pluralize(args)
            format_term(args, plural)

          when 'operation'
            format_operation(args)

          when 'block'
            format_block(args)

          when 'property'
            format_property(args)

          when 'package'
            format_package(args)

          when 'def'
            @@definitions.dig(*args.split('::')) || "<code>#{args}</code>"

          when 'latex'
            args

          when 'table'
            num = @table_nums[args]
            # puts "Table Reference #{args} = #{num}"

            "<em>Table #{num}</em>"

          when 'figure'
            num = @figure_nums[args]
            # puts "Image Reference #{args} = #{num}"            
            "<em>Figure #{num}</em>"

          when "span", "colspan"
            ''

          when "rowspan"
            ''

          when "sect"
            "<em>Section #{args}</em>"

          when "input"
            ''

          when 'cite', 'citetitle'
            if args =~ /MTCPart([0-9])/
              target = case $1
                       when '1'
                         'Protocols'
                         
                       when '2'
                         'Device Information Model'

                       when '3'
                         'Observation Information Model'

                       when '4'
                         'Asset Information Model'

                       when '5'
                         'Interface Interaction Model'

                       else
                         "MTConnect Part #{$1}"
                       end

              format_package(target)
            else
              "<em>#{args}</em>"
            end
            
          when 'markdown'
            convert_markdown_to_html(args)

          when 'url'
            if cp = args.index(':')
              ref = args
              text = args[(cp + 1)..]
            else
              ref = "https://#{args}"
              text = args
            end
            
            "<a href='#{ref}'>#{text}</a>"
            
          else
            args
            
          end
        else
          ''
        end
      end
    end
  end
end

