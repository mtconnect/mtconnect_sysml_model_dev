
module Diagram
  def png_diagram_name
    "./diagrams/types/#{short_name}.png"
  end

  def md_diagram_name
    "./diagrams/types/#{short_name}.md"
  end

  def png_diagram_file_name
    "./#{MarkdownModel.directory}/#{png_diagram_name}"
  end

  def md_diagram_file_name
    "./#{MarkdownModel.directory}/#{md_diagram_name}"
  end

  def png_diagram_exists?
    File.exists?(png_diagram_file_name)      
  end

  def md_diagram_exists?
    File.exists?(md_diagram_file_name)
  end
  
  def generate_diagram(f)
    if md_diagram_exists?
      # puts "** Generating png diagrams #{md_diagram_file_name}"

      f.puts "{{input(#{md_diagram_name})}}\n\n"
    elsif png_diagram_exists?
      # puts "** Generating png diagrams #{png_diagram_file_name}"
      f.puts "![#{@name} Diagram](#{png_diagram_name} \"#{short_name}\")\n\n{{FloatBarrier()}}\n\n"
    end
  end
end