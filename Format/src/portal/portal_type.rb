
require 'type'
require 'portal/helpers'

class Type::Literal
  include PortalHelpers
end

class Operation
  include PortalHelpers
end

class PortalType < Type
  include Document
  include PortalHelpers

  attr_reader :path, :pid, :content

  @@types_by_pid = Hash.new

  def self.type_for_pid(id)
    @@types_by_pid[id.to_sym]
  end

  def initialize(model, e)
    super

    @generated = false
    lits = literals
    unless lits.empty?
      definitions = Hash.new
      lits.sort_by { |lit| lit.name }.each do |lit|
        definitions[lit.name] = convert_markdown_to_html(lit.description.definition)
      end

      Kramdown::Converter::MtcHtml.add_definitions(@name, definitions)
    end
  end
  
  def associate_content(doc, node, path)
    @path = (path.dup << node[:text]).freeze
    @doc = doc
    @tree = node
    @pid = node[:qtitle].to_sym
    @content = @doc.content[@pid]

    @tree[:text] = @content[:title] = decorated

    @@types_by_pid[@pid] = self
  end

  def formatted_path
    "#{@model.formatted_path} / #{format_target}"
  end

  def enumeration_rows
    i = 0
    literals.sort_by { |lit| lit.name }.map.with_index do |lit, i|
      [ i + 1, lit.format_name, lit.introduced, lit.deprecated, lit.updated,
        convert_markdown_to_html(lit.description.definition) ]
    end
  end

  def generate_enumeration
    return unless enumeration?

    @generated = true
    
    characteristics = gen_characteristics
    literals = create_panel('Enumeration Literals',
                            { '#': 50, Name: 300, Int: 40, Dep: 40, Upd: 40, Documentation: -1},
                            enumeration_rows)

    add_tree_node([characteristics, literals])
  end

  def generate_stereotype
    return unless @type == 'uml:Stereotype'

    @generated = true

    characteristics = gen_characteristics
    add_tree_node([characteristics])
  end

  def add_characteristics
    if not @generated and @content
      data = @content.dig(:grid_panel, 0, :data_store, :data)

      unless @documentation.empty?
        data.delete_if { |r| r[:col0].start_with?('Documentation') }
        @documentation.sections.each do |section|
          data << { col0: section.title, col1: convert_markdown_to_html(section.text) }
        end
      end
            
      if data
        data.unshift({ col0: 'Superclass (is-a)', col1: @parents.map { |p| p.format_target }.join(', ') }) if not @parents.empty?
        data << { col0: 'Introduced', col1: introduced } if introduced
        data << { col0: 'Deprecated', col1: deprecated } if deprecated
        if updated
          text = updated.dup
          if prior = prior_version(updated)
            text << " (Previous: #{format_version_link(@name, prior, prior, @pid)})"
          end
          data << { col0: 'Updated', col1: text }
        end
      end
      
    end
  end

  def add_constraints
    return unless @content and @constraints and !@constraints.empty?

    $logger.debug "Adding constraints to #{@name}"

    rows = @constraints.map.with_index do |const, i|
      [ i + 1, convert_markdown_to_html(const.documentation), convert_markdown_to_html("~~~~\n#{const.ocl}\n~~~~") ]
    end

    # Add to the end of the grid
    @content[:grid_panel] << create_panel('Constraints', { '#': 50, 'Error Message': 400, 'OCL Expression': -1 }, rows)
  end

  def add_inversions
    return unless @content

    has_thru = false
    rows = inversions    
    
    return if rows.empty?

    thru = rows.any?(&:thru?)
    rows = rows.map.with_index do |rel, i|
      if thru
        [ i + 1, rel.name, rel.target.type.format_target, rel.final_target.type.format_target ]
      else
        [ i + 1, rel.name, rel.final_target.type.format_target ]
      end
    end

    if thru
      @content[:grid_panel] << create_panel('Part Of', { '#': 64, 'Name': 200, 'Organized By': 250, 'Type': 250 }, rows)    
    else
      @content[:grid_panel] << create_panel('Part Of', { '#': 64, 'Name': 200,  'Type': 250 }, rows)    
    end
  end

  BLANK = ' </br>'
  
  def add_version_to_attributes
    return if @generated or @content.nil? or !@content.include?(:grid_panel)
    
    grid = @content[:grid_panel]    
    grid.each do |panel|
      next if panel[:title].nil? or panel[:title].start_with?('Characteristics')

      rows = panel.dig(:data_store, :data)

      columns = panel[:columns]
      nc = column_index(columns, 'Name')
      next unless nc

      tc = column_index(columns, 'Type')
      mc = column_index(columns, 'Multiplicity')
      dc = column_index(columns, 'Documentation')
      unless dc
        $logger.error "Cannot find Documentaiton for relation"
      end

      fields = panel.dig(:data_store, :fields)

      resize(columns, 'Type', 200)
      resize(columns, 'Multiplicity', 100)
      resize(columns, 'Default Value', 200)
      
      ind_pos = fields.index(nc) + 1
      fields.insert(ind_pos, :int, :dep)
      
      columns.insert(ind_pos,
                     { text: "Int", dataIndex: 'int', flex: 0, width: 64 },
                     { text: "Dep", dataIndex: 'dep', flex: 0, width: 64 })

      if panel[:title].start_with?("Value Properties")
        ro = :ro
        pos = fields.index(mc) + 1
        fields.insert(pos, ro)

        columns.insert(pos,
                       { text: "Read Only", dataIndex: 'ro', flex: 0, width: 84 })
      end
      
      # Get sumbolic versions for data index
      has_thru = false
      dc = dc.to_sym      
      ind = nc.to_sym
      mc = mc.to_sym
      tc = tc.to_sym
      rows.each do |row|
        # Use nokogiri to parse the html and grab the CDATA.
        html = Nokogiri::HTML(row[ind])
        name, type = html.text.delete(" \u{00A0}").split(':').map { |s| s.strip }

        ints, deps = [introduced], [deprecated]

        # Get relationss by name
        rel = relation(name)
        if rel
          ints << rel.introduced
          deps << rel.deprecated
          
          if Relation::Association === rel
            assoc = rel.association
            ints << assoc.introduced
            deps << assoc.deprecated

            doc = assoc.documentation
            if doc and row[dc] == BLANK
              row[dc] = convert_markdown_to_html(doc)
            end

            if rel.thru?
              inter = rel.target.type
            end
          end
          
          if rel.target
            ints << rel.target.introduced
            ints << rel.target.type.introduced
            deps << rel.target.deprecated
            deps << rel.target.type.deprecated
          end


          if row[mc] == BLANK
            row[mc] = 1
          end

          if ro
            row[ro] = (rel.read_only || "False").to_s.capitalize

            if rel.name == 'subType' or rel.name == 'type' and not rel.read_only
              text = row[dc] == BLANK ? '' : "#{row[dc]}<br/><br/>"
              if rel.default
                text << "An unspecified <code>#{rel.name}</code> <b>MUST</b> default to <code>#{rel.default}<code>."
              elsif rel.multiplicity == '1'
                text << "The <code>#{rel.name}</code> <b>MUST</b> be specified"
              end
              row[dc] = text
            end
          end
        else
          $logger.warn "Cannot find relation for #{@name}::#{name}"
        end

        int = ints.compact.max
        dep = deps.compact.max

        type = row[tc]
        if type !~ /navigate/ and type =~ %r{([A-Za-z]+)</div></br>$} and block = find_block($1)
          row[tc] = block.format_target(false)
        end

        if dep
          row[ind] = deprecate_html(row[ind])
        end

        # Add Versions
        row[:int] = int || introduced
        row[:dep] = dep || deprecated

        if inter
          row[:thru] = inter.format_target
          has_thru = true
        end    
      end

      if has_thru
        fields.insert(ind_pos + 2, :thru) 
        columns.insert(ind_pos + 2, { text: "Organized By", dataIndex: 'thru', flex: 0, width: 250 })
      end
    end
  end

  def generate_children_panel
    if @content      
      grid = @content[:grid_panel]
      unless grid
        $logger.warning "Missing grid panel for #{@name}"
      else
        if @relation && @type == 'uml:AssociationClass'
          puts "**** Organizes for: #{@name} #{@type} #{@relation.name}"
          rows = [@relation.source.type].concat(@relation.source.type.children.sort_by(&:name)).
                   map.with_index do |t, i|
            
            [ i + 1, t.format_target, t.introduced, t.deprecated ]
          end
          grid << create_panel('Organizes', { '#': 50, Name: 300, Int: 64, Dep: 64 }, rows)        
        end

        if not @children.empty?
          rows = @children.sort_by(&:name).map.with_index do |child, i|
            [ i + 1, child.format_target, child.introduced, child.deprecated ]
          end
          grid << create_panel('Subclasses', { '#': 50, Name: 300, Int: 64, Dep: 64 }, rows)
        end
      end
    end
  end

  def add_tree_node(panels)
    _, pre = @type.split(':')
    @pid = "#{pre}__#{@id}"
    @doc = @model.doc
    @@types_by_pid[@pid] = self
    icon = icon_for_obj(self)

    n = decorated(@name, true)
    @content = { title: n, path: formatted_path, html_panel: [], grid_panel: panels, image_panel: [] }
    @doc.content[@pid] = @content
    @model.tree[:children] << { text: n, qtitle: @pid, icon: icon, expanded: false, leaf: true }

    add_entry(pre.downcase)
  end

  def generate_operations
    return if @operations.empty?

    unless @tree
      puts "!!!!! Tree not available for #{@pid}"
      return
    end

    @tree[:leaf] = false
    children = @tree[:children] = []
    op_rows = []
    
    path = formatted_path
    @operations.each_with_index do |op, i|
      panels = [op.gen_characteristics]
      results = []
      ret = nil
      rows = op.parameters.map.with_index do |par, i|
        type = Type.type_for_id(par.type) || par.type || 'string'

        if par.direction == 'return' 
          results << [ 'Result', type.format_target, convert_markdown_to_html(par.documentation.definition) ]
          ret = type.format_target
          nil
        elsif par.direction == 'out'
          results << [ par.name, type.format_target, convert_markdown_to_html(par.documentation.definition) ]
          nil
        else
          dflt = par.default ? convert_markdown_to_html("`#{par.default}`") : ''
          int = par.introduced || op.introduced
          dep = par.deprecated || op.deprecated
          pn = dep ? "<strike>#{par.name}</strike>" : par.name
          [ i + 1, pn, int, dep, type.format_target, par.multiplicity, dflt, convert_markdown_to_html(par.documentation.definition) ]
        end
      end.compact
      panels << create_panel('Parameters', { '#': 50, Name: 200, Int: 64, Dep: 64, Type: 150, Multiplicity: 84, 'Default Value': 100, Documentation: -1 }, rows)
      panels << create_panel('Result', { Name: 200, Type: 250, Documentation: -1 }, results) unless results.empty?
      
      content = { title: op.name, path: "#{path} / #{op.format_target}", html_panel: [], grid_panel: panels, image_panel: [] }
      @doc.content[op.pid] = content
      children << { text: op.name, qtitle: op.pid, icon: OperationIcon, expanded: false, leaf: true }

      entry = { id: op.pid, name: "#{op.name} : <i>Opeeration</i>", type: 'operation' }

      op_rows << [ i + 1, op.format_target, op.introduced, op.deprecated, ret, convert_markdown_to_html(op.documentation.definition) ]
      
      @doc.search[:all] << entry
      @doc.search[:block] << entry    
    end

    @content[:grid_panel] << create_panel('Operatiuons', { '#': 50, Name: 200, Int: 64, Dep: 64, Result: 150, Documentation: -1 }, op_rows)    
  end
end
