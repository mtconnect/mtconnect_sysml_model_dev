$: << File.dirname(__FILE__)

module Document

  ROW_FORMAT = %s{format-1="p 0.85in" format-2="p 0.8in" format-3="p 1.3in" format-4="p 1.3in" format-5="p 0.85in" format-6="p 0.5in"}

  def documentation_name
    "./type-sections/#{short_name}.md"
  end

  def documentation_file_name
    "./#{MarkdownModel.directory}/#{documentation_name}"
  end


  def documentation_exists?
    File.exists?(documentation_file_name)
  end

  def generate_documentation(f, num_of_tabs=0)
    tab = "    " * num_of_tabs
    if documentation_exists?
      f.puts "\n{{input(#{documentation_name})}}\n"
    elsif @documentation
      f.puts "\n#{tab}#{@documentation.gsub("\n","\n#{tab}")}\n"
      f.puts "#{tab}#{@additional_documentation.gsub("\n","\n#{tab}")}\n" if @additional_documentation
    end
  end

  def generate_table(columns, justification, rows, caption)
    return <<-EOT
|#{columns.join("|")}|
|#{justification.join("|")}|
|#{rows.map{|r| [r.join("|")]}.join("|\n|")}|
{: caption=\"#{caption}\"}
EOT
  end

  def get_valuetype_documentation(relation, num_of_tabs = 0, property_name = @name)
    tab = "    " * num_of_tabs
    target = relation.final_target.type
    is_primitive_type = target.documentation == "primitive type."
    
    if relation.name == 'units' && relation.default
      return "\n#{tab}The {{property(units)}} of {{property(#{property_name})}} **MUST** be `#{relation.default}`.\n"
    
    elsif relation.name == 'code'
      if relation.default == "N/A"
        return "\n#{tab}The {{property(code)}} is `N/A` for {{property(#{property_name})}}.\n"
      end
      return "\n#{tab}The {{property(code)}} of {{property(#{property_name})}} **MUST** be `#{relation.default}`.\n"
    
    elsif target.type == 'uml:Enumeration'
      return "\n#{tab}The value of {{property(#{property_name})}} **MUST** be one of the `#{target.name}` enumeration. \n"
    
    elsif target.type == 'uml:Class'
      return "\n#{tab}The {{block(Entry)}} {{property(key)}} **MUST** be one or more from the `#{target.name}` keys.\n"
    
    elsif target.type == 'uml:DataType' && !is_primitive_type && relation.multiplicity == '3'
      return "\n#{tab}The value of {{property(#{property_name})}} **MUST** be reported in `#{target.name}_3D`.\n"
    
    elsif is_primitive_type && !relation.multiplicity.end_with?('0') && !relation.multiplicity.end_with?('1')
      return "\n#{tab}The value of {{property(#{property_name})}} **MUST** be a list of `#{target.name}` of size `#{relation.multiplicity}`.\n"
        
    elsif is_primitive_type
      return "\n#{tab}The value of {{property(#{property_name})}} **MUST** be `#{target.name}`.\n"
    
    else
      return "\n#{tab}The value of {{property(#{property_name})}} **MUST** be `#{target.name}`. See {{sect(#{target.name})}}.\n"
    end
  end

  def generate_glossary_entry(glossary_type)
    plural = @name.end_with?('y') ? @name[0...-1]+"ies" : (@name.end_with?('s') ? @name : @name+"s" )
    return <<-EOT
{{newglossaryentry(#{@name})
{
    type={#{glossary_type}},
    name={#{@name}},
    description={#{@documentation}},
    plural={#{plural}}
}}}

EOT
  end
  
  def get_section_documentation(root_model,section_package_name, section_name)
	section_model = root_model.at("//packagedElement[@name='#{section_package_name}']")
	if section_model && section_model.at("//*[@body='#{section_name}']")
		return section_model.at("//*[@body='#{section_name}']").ownedComment['body']
	else
		return ""
	end
  end

  def generate_section_intro(f,root_model,section_package_name, section_name)
    f.puts "\n# #{section_name}\n\n"
    f.puts get_section_documentation(root_model, section_package_name, section_name)
  end
end

module CommonDocument
  attr_reader :root_model, :doc_num, :doc_title, :version_num, :part_dir
  
  def generate_common_docs(root_model, doc_num, doc_title, version_num, part_dir)
  
    @root_model, @doc_num, @doc_title, @version_num, @part_dir = root_model, doc_num, doc_title, version_num, part_dir
    
    generate_main()
    generate_part_intro()
  end

  def generate_main
    common_docs = root_model.at("//packagedElement[@name='Common Documents']")

    main_md_node = common_docs.at("//*[@body='Main Template MD']")
    main_md_doc = main_md_node.ownedComment['body']

    main_md_doc = main_md_doc.gsub("{{input(%MAIN%)}}","{{input(#{@part_dir}.md)}}")

    File.write(File.join(File.dirname(__FILE__), '../../markdown_documentation', @part_dir, 'main.md'), main_md_doc)

    main_tex_node = common_docs.at("//*[@body='Main Template TEX']")
    main_tex_doc = main_tex_node.ownedComment['body']
    
    main_tex_doc = main_tex_doc.gsub("\\docnum{}","\\docnum{#{@doc_num}}")
    main_tex_doc = main_tex_doc.gsub("\\doctitle{}","\\doctitle{#{@doc_title}}")
    main_tex_doc = main_tex_doc.gsub("\\doctitleshort{}","\\doctitleshort{#{@doc_title}}")
    main_tex_doc = main_tex_doc.gsub("\\versionnum{}","\\versionnum{#{@version_num}}")
    main_tex_doc = main_tex_doc.gsub("\\input{%MAIN%}","\\input{#{@part_dir}.tex}")
    
    File.write(File.join(File.dirname(__FILE__), '../../latex_documentation', @part_dir, 'main.tex'), main_tex_doc)

    generate_mtconnect_doc(common_docs, "MTConnect Class", "mtconnect.cls")
    generate_mtconnect_doc(common_docs, "MTConnect References", "mtc.bib")
    generate_mtconnect_doc(common_docs, "MTConnect Specification and Materials", "legal.md")
    generate_mtconnect_doc(common_docs, "External References", "references.bib")
    generate_mtconnect_doc(common_docs, "Acronyms", "acronyms.md")
    generate_appendix(common_docs)
  end

  def generate_mtconnect_doc(common_docs, node_name, file_name, write_mode = 'w')
    node = common_docs.at("//*[@body='#{node_name}']")
    return if not node

    doc = node.ownedComment['body']
    md_path = File.join(File.dirname(__FILE__), '../../markdown_documentation', @part_dir, file_name)
    tex_path = File.join(File.dirname(__FILE__), '../../latex_documentation', @part_dir, file_name)
    
    if file_name.end_with?('.md')
      File.open(md_path , write_mode) do |f|
        f.write(doc)
      end
    else
      File.open(tex_path , write_mode) do |f|
        f.write(doc)
      end
    end
  end
  
  def generate_part_intro
    supporting_docs = @root_model.at("//packagedElement[@name='Supporting Documents']")
    generate_mtconnect_doc(supporting_docs, @part_dir.capitalize + " Introduction", "introduction.md")
  end
  
  def generate_appendix(common_docs)
    generate_mtconnect_doc(common_docs, "Appendix", "appendix.md")
    supporting_docs = @root_model.at("//packagedElement[@name='Supporting Documents']")
    generate_mtconnect_doc(supporting_docs, @part_dir.capitalize + " Appendix", "appendix.md", 'a')
  end
  
end