require 'kramdown'
require 'fileutils'
require 'json'
require 'fileutils'
require 'active_support/inflector'
require 'pp'
require 'nokogiri'

# Icon constants here
EnumTypeIcon = 'images/enum_type_icon.png'.freeze
EnumLiteralIcon = 'images/enum_literal_icon.png'.freeze
PackageIcon = 'images/package_icon.png'.freeze
BlockIcon = 'images/block_class_icon.png'.freeze
  
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

      def self.converter=(value)
        @@converter = value
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
        if el.value =~ /\{\{([a-zA-Z0-9_]+)(\(([^\)]+)\))?\}\}/
          command = $1
          args = $3.gsub(/\\([<>])/, '\1') if $3
          
          case command         
          when 'term'
            "<em>#{args}</em>"
            
          when 'termplural'
            plural = ActiveSupport::Inflector.pluralize(args)
            "<em>#{plural}</em>"

          when 'block', 'property'
            @@converter.format_block(args)

          when 'def'
            @@definitions.path(*args.split(':')) || "<code>#{args}</code>"

          when 'latex'
            args

          when 'table'
            "<em>Table #{args}</em>"

          when 'figure'
            "<em>Figure #{args}</em>"

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

              @@converter.format_package(target)
            else
              "<em>#{args}</em>"
            end
            
          when 'markdown'
            kd = ::Kramdown::Document.new(args.gsub(/<br\/?>/, "\n"), input: 'MTCKramdown')
            kd.to_mtc_html
            
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

class WebReportConverter
  def initialize(js, xmi)
    # Reading XMI model
    File.open(xmi) do |xml|
      xmiDoc = Nokogiri::XML(xml).slop!
      @model = xmiDoc.at('//uml:Model')
    end

    @doc = js_to_json(js)
    @content = @doc['window.content_data_json']
    @search = @doc['window.search_data_json']
    @tree = @doc.path('window.navigation_json')
    @struct = find_section('Structure')

    @enumerations = Hash.new
    @deprecated = Set.new
    @paths = Hash.new
    @stereos = Hash.new

    # Collect all the structures so we can relate them later
    @blocks = Hash.new
    @content.each do |k, v|
      if k =~ /^(Structure|Package)/
        @blocks[v['title']] = k
      end
    end

    Kramdown::Converter::MtcHtml.converter = self
  end

  def js_to_json(file)
    puts "Reading #{file}"
    data = File.read(file)
    
    data.gsub!(/^\};/, '},')
    data.gsub!(/;$/, ',')
    
    data.gsub!(/^(window\.[a-z_]+) = '([^']+)'/i, '"\1": "\2"')
    data.gsub!(/^(window\.[a-z_]+) =/i, '"\1": ')
    
    data.insert(0, '{')
    data.sub!(/,\Z/, "}\n")
    
    puts "Parsing #{file}"
    JSON.parse(data)
  end

  def find_section(sect)
    tree = @tree.detect { |n| n['title'] == sect }
    tree['data'] if tree
  end
  
  def add_license(file)
    # Add the legal docs to the landing page
    puts "Adding licesnse #{file}"
    File.open(file) do |f|
      legal = ::Kramdown::Document.new(f.read, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
      panel = @doc.path('window.index_page_json', 'html_panel', 0)
      
      # Clean up the styling
      panel['html'].sub!(%r{margin-top:300px}, 'margin-top:100px')
      panel['html'].sub!(%r{height: 500px}, 'height: 800px')
      # Add the legal content
      panel['html'].
        sub!(%r{</div>}, "<div style=\"text-align: left; margin-left: 50px; margin-right: 50px;\">#{legal.to_mtc_html}</div></div>")
    end
  end
    

  def convert_markdown_to_html(content)
    data = content.gsub(%r{<(/)?br[ ]*(/)?>}, "\n").gsub('&gt;', '>')
    kd = ::Kramdown::Document.new(data, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
    kd.to_mtc_html.sub(/^<p>/, '').sub(/<\/p>\n\z/m, '')     
  end

  def convert_markdown
    @content.each do |k, v|
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
                deprecated = row['col1'] =~ /DEPRECATED/
              end
            end
          else
            desc = panel['columns'].detect { |col| col['text'].start_with?('Documentation') or col['text'].start_with?('Description') }
            name = panel['columns'].detect { |col| col['text'].start_with?('Name') }
            type = panel['columns'].detect { |col| col['text'].start_with?('Type') }
            
            dc = desc['dataIndex'] if desc
            nc = name['dataIndex'] if name
            tc = type['dataIndex'] if type
            panel.path('data_store', 'data').each do |row|
              if dc and row[dc] != " </br>"
                row[dc] = convert_markdown_to_html(row[dc])
                if nc and row[dc] =~ /deprecated/i
                  row[nc] = deprecate(row[nc])
                end              
              end
              
              if tc and row[tc] =~ /([A-Za-z]+Enum)</ and @enumerations.include?($1)
                row[tc] = format_target(@enumerations[$1], $1, EnumTypeIcon)
              end
            end
          end
        end
        
        if deprecated
          @deprecated << k
          v['title'] = "<strike>#{title}</strike>"
        end
      end
    end  
  end
  
  def format_name(name, icon, text = name)
    "<div title=\"#{name}\" style=\"display: inline !important; white-space: nowrap !important; height: 20px;\">" \
      "<span style=\"vertical-align: middle;\"><img src='#{icon}' width='16' height='16' title='' style=\"vertical-align: bottom;\">" \
      "</span> #{text}</div></br>"
  end

  def deprecated_format_name(name, icon)
    format_name(name, icon, "<strike>#{name}</strike>")
  end

  def format_target(id, name, icon, text = name)
    "<div title=\"#{name}\" style=\"display: inline !important; white-space: nowrap !important; height: 20px;\">" \
      "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\"><span style=\"vertical-align: middle;\">" \
      "<img src='#{icon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span></a>" \
      "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\"> #{text}</a></div>"            
  end
  
  def deprecated_format_target(id, name, icon)
    format_target(id, name, icon, "<strike>#{name}</strike>")
  end
  
  def deprecate(text)
    text.sub(%r{> (.+?)</div></br>$}, '> <strike>\1</strike>\2</div>')
  end

  def format_block(block)
    if b = @blocks[block]
      "<a><span style=\"vertical-align: middle;\">" \
      "<img src='#{BlockIcon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span>" \
      "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{b}');return false;\"> #{block}</a>"            
    else
      "<code>#{block}</code>"                
    end                    
  end

  def format_package(package)
    if b = @blocks[package]
      "<a><span style=\"vertical-align: middle;\">" \
        "<img src='#{PackageIcon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span>" \
        "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{b}');return false;\"> #{package}</a>"            
    else
      "<em>#{package}</em>"                
    end                    
  end

  def collect_comments(model, name)
    comments = model.xpath("//packagedElement[@name='#{name}' and (@xmi:type='uml:Package' or @xmi:type='uml:Profile')]")
    recurse = lambda { |ele| [ ele['body'], ele.xpath('./ownedComment').map { |e2| recurse.call(e2) } ] }
    comments.map { |ele| recurse.call(ele) }.flatten.compact.join("\n\n")
  end

  def gen_characteristics(*rows)
    data = rows.map { |col1, col2| { col0: "#{col1} ", col1: col2 } }
    
    { title: 'Characteristics ', hideHeaders: true, collapsible: true,
      data_store: { fields: ['col0', 'col1'], data: data },
      columns: [ { text: 'col0', dataIndex: 'col0', flex: 0, width: 192 },
                 { text: 'col1', dataIndex: 'col1', flex: 1, width: -1 } ] }    
  end

  def find_element(id)
    model = @xmi_map[id]
    return unless model
    
    xmi_id = model['xmi:id']
    [xmi_id, model]
  end

  def find_stereos(id)
    return nil unless @stereotypes.include?(id)
    prof = @stereotypes[id]

    prof.map { |t| "<em>&lt;&lt;#{t}&gt;&gt;</em>" }.join(' ')    
  end

  def document_packages
    @content.each do |k, v|
      if k =~ /^Package__/
        name = v['title']
        xmi_id, model = find_element(k)
        if model
          stereos = find_stereos(xmi_id)
          if stereos
            @stereos[k] = stereos
            v['title'] = "#{stereos} #{name}"
          end
        end
        
        grid = v['grid_panel']
        if grid and grid.empty?
          text = collect_comments(@model, name)
          unless text.empty?
            # Create documentation w/ characteristics section
            content = "<p>#{convert_markdown_to_html(text)}</p>"
            
            grid[0] = gen_characteristics(['Name', format_target(k, name, PackageIcon)],
                                          ['Documentation', content])

          end
        end
      end
    end
  end

  def find_path(*path)
    list = @struct
    res = nil
    path.each do |text|
      res = list.detect { |node| node['text'] == text }
      break unless res
      list = res['children']
    end
    res
  end

  def get_comment(node)
    vname = node['name']
    comment, = node.xpath('./ownedComment')
    if comment
      text = convert_markdown_to_html(comment['body'])
      if text =~ /deprecated/i
        lit = deprecated_format_name(vname, EnumLiteralIcon)
      end
    end
    text
  end

  def add_entry(id, name)
    entry = { id: id, 'name' => "#{name} : <i>Block</i>", type: "block" }
    @search['all'] << entry
    @search['block'] << entry
  end

  def enumeration_rows(ele)
      name = ele['name']
      i = 0
      definitions = Hash.new    
      rows = ele.xpath('./ownedLiteral[@xmi:type="uml:EnumerationLiteral"]').sort_by { |value| value['name'] }.map do |value|
        i += 1
        vname = value['name']
        lit = format_name(vname, EnumLiteralIcon)
        text = get_comment(value)
        definitions[vname] = text if text

        { col0: "#{i} </br>", col1: lit, col2: text.to_s }
      end
      
      # Add the definitions to the markdown converter
      Kramdown::Converter::MtcHtml.add_definitions(name, definitions)

      rows
  end

  def generate_enumerations
    # The static package id of 'DataTypes'
    profile = 'Package__30f1303c-9595-4a32-a8e4-99f3ff79459f'
    package = 'Package__9f1dc926-575b-4c4d-bc3e-f0b64d617dfc'
    root = "#{format_target(profile, 'Profile', PackageIcon)} / #{format_target(package, 'DataTypes', PackageIcon)}"

    data_types = find_path('Profile', 'DataTypes')
    unless data_types
      puts "Could not find data types"
      return
    end

    children = data_types['children']
    
    @model.xpath("//packagedElement[@xmi:type='uml:Enumeration']").sort_by { |ele| ele['name'] }.each do |ele|            
      name = ele['name']
      enum = "Enumeration__#{ele['xmi:id']}"
      @enumerations[name] = enum

      children << { text: name, qtitle: enum, icon: EnumTypeIcon, expanded: false, leaf: true }
      
      col1 = format_target(enum, name, EnumTypeIcon)
      path = "#{root} / #{col1}"      
      
      # Create characteristics section of the page
      characteristics = gen_characteristics(['Name', col1])

      # Collect all the literals and build the table. Also collect them for {{def(...)}} dereferencing
      rows = enumeration_rows(ele)
      
      # Create the grid of literals
      literals = { title: 'Enumeration Literals', hideHeaders: false, collapsible: true,
                   data_store: { fields: ['col0', 'col1', 'col2'], data: rows },
                   columns: [ { text: '# ', dataIndex: 'col0', flex: 0, width: 84 },
                              { text: 'Name ', dataIndex: 'col1', flex: 0, width: 300 },
                              { text: 'Documentation ', dataIndex: 'col2', flex: 1, width: -1 } ] }
      
      # Add the items to the search
      add_entry(enum, name)
      @content[enum] = { title: name, path: path, html_panel: [], grid_panel: [characteristics, literals], image_panel: [] }
    end    
  end

  def generate_stereotypes
    profile = 'Package__30f1303c-9595-4a32-a8e4-99f3ff79459f'
    package = 'Package__8cc92b6d-16e3-4b08-acc8-1f8120d7d68c'
    root = "#{format_target(profile, 'Profile', PackageIcon)} / #{format_target(package, 'DataTypes', PackageIcon)}"
    
    stereo = find_path('Profile', 'Stereotypes')
    children = stereo['children']

    @model.xpath("//packagedElement[@name='Stereotypes' and @xmi:type='uml:Package']/packagedElement[@xmi:type='uml:Stereotype']").
      sort_by { |ele| ele['name'] }.each do |ele|            
      name = ele['name']
      st = "Stereotype__#{ele['xmi:id']}"

      children << { text: name, qtitle: st, icon: BlockIcon, expanded: false, leaf: true }

      col1 = format_target(st, name, BlockIcon)
      path = "#{root} / #{col1}"

      desc = get_comment(ele)
      
      # Create characteristics section of the page
      characteristics = gen_characteristics(['Name', col1 ], ['Documentation', desc.to_s ])
      
      @content[st] = { title: name, path: path, html_panel: [], grid_panel: [characteristics], image_panel: [] }
      add_entry(st, name)
    end
    
  end

  def xmi_path(node)
    node.ancestors.reverse.map { |a| a['name'] }.compact[1..-1]
  end

  def match_count(p1, p2)
    p1.zip(p2).each_with_index { |a, i| return i unless a[0] == a[1] }
    return [p1.length, p2.length].min
  end

  def add_parent(model, target, characteristics)
    # Find its parent
    parent, = model.xpath('./generalization').map do |g|
      if id = g['general']
        parent = @xmi_blocks[id]
        [parent, match_count(target, xmi_path(parent))] if parent
      else
        nil
      end
    end.compact.select { |node, m| m > 0 }.sort_by { |node, m| -m }.first
    
    # If there is a superclass and it is not a term
    if parent
      # Find the parent in the content
      name = parent['name']
      
      # Insert a row at the beginning
      characteristics.path('data_store', 'data').unshift({ col0: 'Parent ', col1: format_block(name) })
    end        
  end

  def add_model_comments(model, characteristics)
    # Check for comments
    model.xpath('./ownedComment/ownedComment').each do  |comment|
      # A two level nested comment has the parent body as title and the child body the markdown conent
      # Create a row in the grid at the end of the characteristics block
      characteristics.path('data_store', 'data') << { col0: comment.parent['body'], col1:  convert_markdown_to_html(comment['body']) }
    end
  end

  def add_constraints(model, grid)
    # Check for owned rules
    rules = model.xpath('./ownedRule/specification').map do |rule|
      # Look for the error message associated with the validation rule
      id = rule.parent['xmi:id']
      error, = @model.xpath("//Validation_Profile:validationRule[@base_Constraint='#{id}']")
      message = error['errorMessage'] if error

      # create a row in the grid using the parent name and the spec body as code
      { col0: convert_markdown_to_html(message.to_s),
        col1: "<code>#{rule.body.text}</code>" }
    end
    
    if rules and !rules.empty?
      # Rules are added as another grid with two columns. 
      constraints = { title: 'Constraints', hideHeaders: false, collapsible: true,
                      data_store: { fields: ['col0', 'col1'], data: rules },
                      columns: [ { text: 'Error Message', dataIndex: 'col0', flex: 0, width: 600 },
                                 { text: 'OCL Expression ', dataIndex: 'col1', flex: 1, width: -1 }] }
      # Add to the end of the grid
      grid << constraints            
    end
  end

  def add_model_content
    # Second pass
    @content.each do |k, v|
      if k =~ /^Structure/
        title = v['title']
        title = $1 if title =~ /<strike>([^<]+)/

        xmi_id, model = find_element(k)
        unless model
          puts "Error: Cannot find model for #{title} and path #{@paths[k].inspect}"
          next
        end

        stereos = find_stereos(xmi_id)
        if stereos
          @stereos[k] = stereos
          v['title'] = (stereos + ' ') << v['title']
        end
        
        grid = v['grid_panel']          
        characteristics = grid[0]
        if characteristics and characteristics['title'].start_with?('Characteristics')
          add_parent(model, @paths[k], characteristics)
          add_model_comments(model, characteristics)            
        end
        
        add_constraints(model, grid)
      end
    end

    puts
  end
  
  def deprecate_tree
    recurse = lambda do |node|
      id = node['qtitle']
      if @deprecated.include?(id)
        node['text'] = "<strike>#{node['text']}</strike>"
      end
      if @stereos.include?(id)
        text = @stereos[id]
        node['text'] = "#{text} #{node['text']}"
      end
      if node['children']
        node['children'].each { |c| recurse.call(c) }
      end
    end

    @struct.each do |node|
      recurse.call(node)
    end
  end

  def merge(list1, list2, indent = 0)
    list1.each do |node1|
      text = node1['text']
      space = '  ' * indent
      node2 = list2.detect { |n| n['text'] == text }
      # puts "#{space}Node: #{text}"
      if node2
        # If the nodes entities don't match, then append this node to the parent
        t1, = node1['qtitle'].split('_', 2)
        t2, = node2['qtitle'].split('_', 2)

        if t1 != t2
          list2 << node1 if t1 != 'EmptyContent'
        elsif node1['qtitle'] != node2['qtitle']
          # First check if these are the same types, don't merge a diagram to a Structure
          
          
          # See if we can merge the grids and children
          qn1, qn2 = @content[node1['qtitle']], @content[node2['qtitle']]
          gp1, gp2 = qn1['grid_panel'], qn2['grid_panel']

          if !gp1.empty? and gp2.empty?
            # puts "#{space}  Replace grid: #{text}"            
            qn2['grid_panel'] = gp1
          elsif !gp1.empty? and !gp2.empty?
            # puts "#{space}  Merging grids: #{text}"
            qn2['grid_panel'].concat(qn1['grid_panel'])
          end
        end

        # Recurse if there are children of both trees
        c1, c2 = node1['children'], node2['children']
        if c1 and c2.nil?
          # puts "#{space}  Children in only one branch: #{text}"
          node2['leaf'] = false
          node2['children'] = c1
        elsif c1 and c2
          # puts "#{space}  Merging children: #{text}"
          merge(c1, c2, indent + 1)
        end
      else
        # If there is no child, add this child
        # puts "#{space}  Adding node: #{text}"
        list2 << node1
      end
    end    
  end

  def merge_diagrams
    diagrams = find_section('Diagrams')
    behavior = find_section('Behavior')
    structure = find_section('Structure')

    # Parallel recures diagrams and structure combining common nodes
    # puts "\n----------------------------------"
    merge(diagrams, structure)
    # puts "\n----------------------------------"
    merge(behavior, structure)

    @tree.delete_if { |node| node['title'] == 'Diagrams' } 
    @tree.delete_if { |node| node['title'] == 'Interfaces' } 
    @tree.delete_if { |node| node['title'] == 'Behavior' }

    @xmi_blocks = Hash.new
    @xmi_map = Hash.new
    eles = Hash.new
    @model.xpath("//packagedElement").each do |m|
      type = m['xmi:type']
      next unless type =~ /^uml:(Package|Class|AssociationClass)/
      
      path = xmi_path(m) << m['name']
      eles[path] = m
      @xmi_blocks[m['xmi:id']] = m
    end

    @stereotypes = Hash.new { |h, k| h[k] = [] }
    @model.xpath("/xmi:XMI/*").select { |m| m.namespace.prefix == 'Profile' }.each do |m|
      @stereotypes[m['base_Element']] << m.name
    end
    
    recurse = lambda do |node, path|
      path = (path.dup << node['text']).freeze
      @paths[node['qtitle']] = path
      @xmi_map[node['qtitle']] = eles[path]
      
      if node['children']
        node['children'].each { |c| recurse.call(c, path) }
      end
    end
    @struct.each do |node|
      recurse.call(node, [])
    end
  end

  def convert
    puts "\nMerging Diagrams into Structure"
    merge_diagrams    

    puts "\nGenerating enumerations"
    generate_enumerations

    puts "\nGenerating Stereotypes"
    generate_stereotypes

    puts "\nDocument packages"
    document_packages
  
    puts "\nConverting markdown" 
    convert_markdown

    puts "\nAdding additional model content"
    add_model_content

    puts "\nDeprecating classes in tree"
    deprecate_tree

    # Sort the search items
    @search['all'].sort_by! { |e| e['name'] }
    @search['block'].sort_by! { |e| e['name'] }
  end

  def write(file)
    puts "Writing out #{file}"
    File.open(file, 'w') do |f|
      @doc.each do |k, v|
        f.write("#{k} = ");
        f.write(JSON.fast_generate(v, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
        f.write(";\n")
      end
    end    
  end
end

if __FILE__ == $PROGRAM_NAME
  dir = ARGV[0] || "../WebReport"

  puts "Working on directory #{dir}"
  
  index = File.expand_path("#{dir}/index.html", File.dirname(__FILE__))
  file = File.expand_path("#{dir}/data.js", File.dirname(__FILE__))
  resource = File.expand_path("#{dir}/resource.js", File.dirname(__FILE__))
  res_formatted = File.expand_path("#{dir}/resource.formatted.js", File.dirname(__FILE__))
  output = File.expand_path("#{dir}/data.formatted.js", File.dirname(__FILE__))
  logo = File.expand_path("#{dir}/images/logo.png", File.dirname(__FILE__))
  mtconnect = File.expand_path('./MTConnect.png', File.dirname(__FILE__))
  xmi = File.expand_path('../MTConnect SysML Model.xml', File.dirname(__FILE__))
  legal = File.expand_path('./legal.md', File.dirname(__FILE__))
  src_images = File.expand_path('./images', File.dirname(__FILE__))
  dest_images = File.expand_path("#{dir}/images", File.dirname(__FILE__))
  
  # Install our logo
  FileUtils.cp(mtconnect, logo)

  puts "Copying images to #{dest_images}"
  FileUtils.cp_r(Dir.glob("#{src_images}/*"), dest_images)
    

  text = File.open(index).read
  text.sub!(/src="data\.js"/, 'src="data.formatted.js"')
  text.sub!(/src="resource\.js"/, 'src="resource.formatted.js"')
  File.open(index, 'w') { |f| f.write(text) }
  
  converter = WebReportConverter.new(file, xmi)
  converter.add_license(legal)
  converter.convert
  converter.write(output)

  data = File.read(resource).sub(/^window\.resource =/, '').gsub(/^([ \t]+[a-z_]+)[ ]+:/, '\1:')
  res = eval(data)
  lp = res.path(:logo_panel, :logo)
  lp['height'] = '60px'
  lp['width'] = '205px'

  puts "Rewriting the resource file: #{res_formatted}"
  File.open(res_formatted, 'w') do |f|
    f.write "window.resource = "
    f.write(JSON.fast_generate(res, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
  end
end
