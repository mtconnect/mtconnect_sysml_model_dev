require 'diagram'
require 'portal/helpers'

class PortalDiagram < Diagram
  include PortalHelpers
  
  @@diagrams_by_id = Hash.new

  def self.diagram_by_id(id)
    @@diagrams_by_id[id]
  end
  
  def document_diagram
    return if @content.nil? or @documentation.nil? or @documentation.empty?

    $logger.info "Documenting diagram: #{name}"

    grid = @content[:grid_panel] if @content
    if grid
      grid.unshift gen_characteristics
    end
  end


  def associate_content(doc, node, path)
    @path = (path.dup << node[:text]).freeze
    @doc = doc
    @tree = node
    @pid = node[:qtitle].to_sym
    @content = @doc.content[@pid]

    @tree[:text] = @content[:title] = decorated

    @@diagrams_by_id[@pid] = self
  end
end
