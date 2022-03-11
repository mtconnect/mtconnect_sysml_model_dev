require 'active_support/inflector'

# Icon constants here
EnumTypeIcon = 'images/enum_type_icon.png'.freeze
EnumLiteralIcon = 'images/enum_literal_icon.png'.freeze
PackageIcon = 'images/package_icon.png'.freeze
BlockIcon = 'images/block_class_icon.png'.freeze
OperationIcon = 'images/operation_icon.png'.freeze
DiagramIcon = 'images/diagram_icon.png'.freeze

module PortalHelpers
  def convert_markdown_to_html(content)
    data = content.to_s.gsub(%r{<(/)?br[ ]*(/)?>}, "\n").gsub('&gt;', '>')
    kd = ::Kramdown::Document.new(data, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true, math_engine: :katex})
    kd.to_mtc_html.sub(/^<p>/, '').sub(/<\/p>\n\z/m, '')     
  end

  def resize(columns, name, width)
    col = columns.detect { |c| c[:text] and c[:text].start_with?(name) }
    col[:width] = width if col
  end

  def format_name_html(name, icon, text = name)
    "<span style=\"vertical-align: middle;\"><img src='#{icon}' width='16' height='16' title='' style=\"vertical-align: bottom;\">" \
      "</span>&nbsp;#{text}"
  end

  def deprecated_format_name_html(name, icon)
    format_name_html(name, icon, "<strike>#{name}</strike>")
  end

  def format_target_html(id, name, icon, text = name)
    "<a title=\"#{name}\" href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\"><span style=\"vertical-align: middle;\">" \
      "<img src='#{icon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span></a>" \
      "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{id}');return false;\">&nbsp;#{text}</a>" 
  end

  def deprecated_format_target(id, name, icon)
    format_target_html(id, name, icon, "<strike>#{name}</strike>")
  end
  
  def deprecate_html(text)
    text.sub(%r{> (.+?)</div></br>$}, '>&nbsp;<strike>\1</strike>\2</div>')
  end

  def find_block(name)
    if name.include?('::')
      package, name = name.split('::')
      model = PortalModel.model_for_name(package)      
      block =  model.types.find { |t| t.name == name } if model
    else
      block = PortalType.type_for_name(name)
    end

    return block
  end

  def format_block(block)
    if b = find_block(block)
      b.format_target(false)
    else
      "<code>#{block}</code>"                
    end                    
  end

  def format_package(package)
    if b = PortalModel.model_for_name(package)
      b.format_target(false)
    else
      "<em>#{package}</em>"                
    end                    
  end

  def format_term(term, text = term)
    if t = PortalType.term_for_name(term) and not t.documentation.empty?
      d = t.documentation.definition
      title = d.to_s.gsub(/\{\{(term(plural)?|cite)\(([^)]+)\)\}\}/) do |m|
        t = $3
        if $2
          ActiveSupport::Inflector.pluralize(t)
        else
          t
        end
      end
      %{<span class="hoverterm" title="#{title}">#{text}</span>}
    else
      "<em>#{text}</em>"
    end
  end    

  def format_operation(name)
    operation, block, package = name.split('::').reverse
    if package
      model = PortalModel.model_for_name(package)
      type = model.types.find { |t| t.name == block } if model
    else
      type = PortalType.type_for_name(name)
    end

    op = type.operations.find { |o| o.name == operation } if type
    if op
      op.format_target(false)
    else
      "<code>#{block}::#{operation}</code>"
    end
  end

  def icon_for_obj(obj)
    icon = nil
    case obj
    when PortalType, LazyPointer
      if obj.enumeration?
        icon = EnumTypeIcon
      else
        icon = BlockIcon
      end
      
    when PortalModel
      icon = PackageIcon

    when Type::Literal
      icon = EnumLiteralIcon

    when Operation
      icon = OperationIcon

    when PortalDiagram
      icon = DiagramIcon

    else
      $logger.error "!!!! Unknown type: #{obj.class}"
    end
    icon
  end

  def decorated(text = @name, title = true)
    text = (respond_to?(:abstract?) and abstract?) ? "<em>&lt;&lt;abstract&gt;&gt&nbsp;#{text}</em>" : text
    text = deprecated ? "<strike>#{text}</strike>" : text
    if @stereotypes
      sts = @stereotypes.select { |s| s.name != 'normative' and s.name != 'deprecated' }.map { |s| s.html }
    end
    text = if sts.nil? or sts.empty?
             text
           else
             "<em>#{sts.join(' ')}</em>&nbsp;#{text}"
           end

    if not title
      text = case self
             when PortalType, Operation
               "<code>#{text}</code>"
               
             when PortalModel
               "<em>#{text}</em>"

             else
               text
             end
    end

    text
  end

  def format_target_obj(obj, title = true)
    return obj if String === obj
    icon = icon_for_obj(obj)
    pid = obj.pid
    puts "!!! No PID: #{obj.model.name}::#{obj.name}" unless pid
    text = decorated(obj.name, title)
    pid ? format_target_html(pid, obj.name, icon, text) : format_name_html(obj.name, icon, text)
  end
  
  def format_name_obj(obj, title = true)
    return obj if String === obj
    icon = icon_for_obj(obj)
    text = decorated(obj.name, title)
    format_name_html(obj.name, icon, text)
  end

  def format_target(title = true)
    format_target_obj(self, title)
  end

  def format_name(title = true)
    format_name_obj(self, title)
  end

  def create_panel(title, columns, rows, hide: false, collapse: true)
    fields = Array(0...(columns.length)).map { |i| "col#{i}" }
    columns = columns.map.with_index do |col, i|
      case col
      when String
        name = col
        width = -1
        
      when Array
        name, width = col
        width ||= -1
        
      else
        name = "col#{i}"
        width = -1 
      end
      flex = width == -1 ? 1 : 0
      { text:"#{name} ", dataIndex: "col#{i}", flex: flex, width: width }
    end

    data = rows.map do |row|
      Hash[*fields.zip(row).flatten]
    end

    panel = { title: "#{title} ", hideHeaders: hide, collapsible: collapse,
              data_store: { fields: fields, data: data },
              columns: columns }
  end
  
  def gen_characteristics
    rows = []
    rows << ['Parent', get_parent.format_target(true) ] if respond_to? :get_parent and get_parent
    rows << ['Name', format_name(true)]
    if not self.is_a?(Model) and @documentation and !@documentation.empty?
      @documentation.sections.each do |section|
        rows << [section.title, convert_markdown_to_html(section.text)]
      end
    end
    rows << ['Introduced', introduced] if introduced
    rows << ['Deprecated', deprecated] if deprecated

    create_panel('Characteristics', { name: 192, text: -1 }, rows, hide: true)
  end

  def add_entry(type = 'block')
    entry = { id: @pid, name: "#{@name} : <i>#{type.capitalize}</i>", type: type }
    @doc.search[:all] << entry
    @doc.search[:block] << entry
  end
end
