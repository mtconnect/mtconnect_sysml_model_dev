
module PortalHelpers
  def convert_markdown_to_html(content)
    data = content.gsub(%r{<(/)?br[ ]*(/)?>}, "\n").gsub('&gt;', '>')
    kd = ::Kramdown::Document.new(data, {input: 'MTCKramdown', html_to_native: false, parse_block_html: true})
    kd.to_mtc_html.sub(/^<p>/, '').sub(/<\/p>\n\z/m, '')     
  end

  def resize(columns, name, width)
    col = columns.detect { |c| c['text'] and c['text'].start_with?(name) }
    col['width'] = width if col
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
    if b = PortalType.type_for_name(block)
      "<a><span style=\"vertical-align: middle;\">" \
      "<img src='#{BlockIcon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span>" \
      "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{b.pid}');return false;\"> #{block}</a>"            
    else
      "<code>#{block}</code>"                
    end                    
  end

  def format_package(package)
    if b = PortalModel.model_for_name(package)
      "<a><span style=\"vertical-align: middle;\">" \
        "<img src='#{PackageIcon}' width='16' height='16' title='' style=\"vertical-align: bottom;\"></span>" \
        "<a href=\"\" target=\"_blank\" onclick=\"navigate('#{b.pid}');return false;\"> #{package}</a>"            
    else
      "<em>#{package}</em>"                
    end                    
  end

  def format_obj(obj)
    dep = obj.deprecated
    pid = obj.pid
    
    case obj
    when PortalType, Type::LazyPointer
      if obj.enumeration?
        icon = EnumTypeIcon
      else
        icon = BlockIcon
      end
      
    when PortalModel
      icon = PackageIcon

    when Type::Literal
      icon = EnumLiteralIcon

    else
      $logger.error "!!!! Unknown type: #{obj.class}"
    end

    if dep
      text = "<strike>#{obj.name}</strike>"
    else
      text = obj.name
    end
    
    if pid
      format_target(pid, obj.name, icon, text)
    else
      format_name(obj.name, icon, text)
    end            
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
  
  def gen_characteristics(*rows)        
    rows << ['Introduced', introduced] if introduced
    rows << ['Deprecated', deprecated] if deprecated
    
    create_panel('Characteristics', { name: 192, text: -1 }, rows, hide: true)
  end

  def add_entry
    entry = { id: @pid, 'name' => "#{@name} : <i>Block</i>", type: "block" }
    @doc.search['all'] << entry
    @doc.search['block'] << entry
  end
end
