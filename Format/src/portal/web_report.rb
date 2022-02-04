
class WebReport
  include PortalHelpers
  
  attr_reader :doc, :content, :search, :tree, :struct
    
  def initialize(file)
    @doc = js_to_json(file)
    @content = @doc['window.content_data_json']
    @search = @doc['window.search_data_json']
    @tree = @doc.path('window.navigation_json')
    @struct = find_section('Structure')
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
    
    $logger.info "Parsing #{file}"
    JSON.parse(data)
  end

  def update_index(index)
    text = File.open(index).read
    text.sub!(/src="data\.js"/, 'src="data.formatted.js"')
    text.sub!(/src="resource\.js"/, 'src="resource.formatted.js"')
    File.open(index, 'w') { |f| f.write(text) }
  end

  def update_resources(resource, res_formatted)
    data = File.read(resource).sub(/^window\.resource =/, '').gsub(/^([ \t]+[a-z_]+)[ ]+:/, '\1:')
    res = eval(data)
    lp = res.path(:logo_panel, :logo)
    lp['height'] = '60px'
    lp['width'] = '205px'
    
    $logger.info "Rewriting the resource file: #{res_formatted}"
    File.open(res_formatted, 'w') do |f|
      f.write "window.resource = "
      f.write(JSON.fast_generate(res, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
    end    
  end

  def write(file)
    # Sort the search items
    @search['all'].sort_by! { |e| e['name'] }
    @search['block'].sort_by! { |e| e['name'] }
    
    order = [ 'Fundamentals',
              'Device Information Model',
              'Observation Information Model',
              'Asset Information Model',
              'Interface Interaction Model',
              'Profile',
              'Glossary' ]
    @struct.sort_by! { |node| order.index(node['text']) }
    
    $logger.info "Writing out #{file}"
    File.open(file, 'w') do |f|
      @doc.each do |k, v|
        f.write("#{k} = ");
        f.write(JSON.fast_generate(v, indent: '  ', array_nl: "\n", object_nl: "\n", space: ' ' ))
        f.write(";\n")
      end
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
    $logger.info "Merging Diagrams"
      
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
  end

  def find_section(sect)
    tree = @tree.detect { |n| n['title'] == sect }
    tree['data'] if tree
  end

  def add_license(comment)
    legal = convert_markdown_to_html(comment)

    
    # Add the legal docs to the landing page
    panel = @doc.path('window.index_page_json', 'html_panel', 0)
    
    # Clean up the styling
    panel['html'].sub!(%r{margin-top:300px}, 'margin-top:100px')
    panel['html'].sub!(%r{height: 500px}, 'height: 800px')
    # Add the legal content
    panel['html'].
      sub!(%r{</div>}, "<div style=\"text-align: left; margin-left: 50px; margin-right: 50px;\">#{legal}</div></div>")
  end

  def deprecate_tree
    recurse = lambda do |node|
      pid = node['qtitle']
      obj = PortalType.type_for_pid(pid) || PortalModel.model_for_pid(pid)
      if obj and obj.deprecated
        node['text'] = "<strike>#{node['text']}</strike>"
      end

      if chld = node['children']
        chld.each { |c| recurse.call(c) }
      end
    end

    @struct.each do |node|
      recurse.call(node)
    end
  end

  def convert_markdown
    @content.each do |k, v|
      if k =~ /^(Glossary|Diagram|Structure)/
        title = v['title']
        obj = PortalType.type_for_pid(k) || PortalModel.model_for_pid(k)
        
        deprecated = obj && obj.deprecated
        
        # Scan the grid panel looking for content
        panels = v['grid_panel']
        panels.each do |panel|
          if panel['hideHeaders'] and panel.path('data_store', 'fields').length == 2
            # Look for documentation
            panel.path('data_store', 'data').each do |row|
              if row['col0'].start_with?('Documentation')
                row['col1'] = convert_markdown_to_html(row['col1'])
                deprecated ||= row['col1'] =~ /DEPRECATED/
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
              
              if tc and row[tc] =~ /([A-Za-z]+Enum)</ and type = PortalType.type_for_name($1)
                row[tc] = format_obj(type)
              end
            end
          end
        end
        
        if deprecated
          v['title'] = "<strike>#{title}</strike>"
        end
      end
    end
  end
end

