
require 'type'
require 'portal/helpers'

class PortalType < Type
  include Document
  include PortalHelpers

  attr_reader :path, :pid, :content

  @@types_by_pid = Hash.new

  def self.type_for_pid(id)
    @@types_by_pid[id]
  end

  def initialize(model, e)
    super

    unless @literals.empty?
      definitions = Hash.new
      @literals.sort_by { |lit| lit.name }.each do |lit|
        definitions[lit.name] = lit.description
      end

      Kramdown::Converter::MtcHtml.add_definitions(@name, definitions)
    end
  end
  
  def associate_content(doc, node, path)
    @path = (path.dup << node['text']).freeze
    @doc = doc
    @pid = node['qtitle']
    @content = @doc.content[@pid]

    @@types_by_pid[@pid] = self
  end

end
