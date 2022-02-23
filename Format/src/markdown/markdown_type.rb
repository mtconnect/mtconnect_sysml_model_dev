require 'set'
require 'documents'
require 'type'
require 'diagrams'

class MarkdownType < Type
  include Diagrams
  include Document

  def generate_types(f)
    $logger.info "Generating docs for #{@name}"
    relations = @relations.select do |r|
      $logger.debug "  Looking for docs for #{r.target.inspect}" if r.target && r.target.type.nil?
      r.type != "uml:Constraint" &&
      (r.documentation ||
        r.target.type.type == "uml:Enumeration" ||
        !r.documentation
      ) &&
      defined?(r.final_target.type) &&
      @model.name.split("Type")[0] != r.final_target.type.name &&
      r.visibility == "public" &&
      r.name != "Supertype"
    end

    unless relations.empty?

      value_properties = relations.select {|a| a.property_stereotype == "" || a.property_stereotype == "ValueProperty"}
      reference_properties = relations.select {|a| a.property_stereotype == "ReferenceProperty"}
      part_properties = relations.select {|a| a.property_stereotype == "PartProperty"}
      
      if model_has_mtconnect_supertype?
        relations.each do |r|
          next unless r.redefinesProperty
          name = r.association_name ? r.association_name : r.name
          target = r.final_target.type
          if name == "result" 
            f.puts get_valuetype_documentation(r)
            if target.type == "uml:Enumeration"
              target.generate_enumerations(f)
            elsif target.type == "uml:Class"
              target.generate_entrykeys(f)
            end
          elsif name == "units" && r.default
            f.puts get_valuetype_documentation(r)
          elsif (name == "type" || name == "subType") && !r.default
            update_dataitemtypes_doc(target)
            stereo = target.stereotype!="" ? "`\<\<#{target.stereotype}\>\>`" : ""
            f.puts "\nThe value of #{stereo}{{property(#{name})}} with {{property(category)}} `#{@name.upcase}` **MUST** be one of the following:\n\n" if name == "type"
            f.puts "\nThe value of #{stereo}{{property(#{name})}} for {{block(DataItem)}} **MUST** be one of the following:\n\n" if name == "subType"
            target.literals.sort_by! { |t| t.name }
            target.literals.each do |lit|
              if type_has_subtypes?(lit)
                subtypes_list_str = @model.generator.dataitemtypes[lit.name]["subTypes"].join(", ")
                lit_subtypes = "\n\n    Subtypes of `#{lit.name}` : #{subtypes_list_str}.\n\n"
              end
              f.puts "\n* `#{lit.name}` \n\n    #{lit.description.gsub("\n", "\n    ")}#{lit_subtypes}"
            end
          end
        end
      end      
      generate_value_property_doc(f, value_properties) unless value_properties.empty?
      generate_associated_property_doc(f, reference_properties, "Reference") unless reference_properties.empty?
      generate_associated_property_doc(f, part_properties, "Part") unless part_properties.empty?
      generate_observation_type_subtypes(f) if observation_type_has_subtypes?
    end    
  end
  
  def generate_observation_type_subtypes(f)
    f.puts "\n#### Subtypes of #{@name}\n\n"
    @subtypes.each do |subtype|
      if defined?(subtype.relation("subType").default)
        f.puts "\n* `#{subtype.relation("subType").default}`\n"
        subtype.generate_documentation(f, 1)
        subtype.relations.each do |r|
          name = r.association_name ? r.association_name : r.name
          if r.redefinesProperty && name == "result"
            f.puts get_valuetype_documentation(r, 1)
            target = r.final_target.type
            if (target.type == "uml:Enumeration" &&
                !@model.generator.enums.include?(target.name))
              target.generate_enumerations(f, 1)
            end
          end
        end
      end
    end
  end

  def generate_value_property_doc(f, value_properties)
    tbl_rows = []
    value_properties.each do |r|
      next if r.redefinesProperty && model_has_mtconnect_supertype?
      name = r.association_name ? r.association_name : r.name
      target = r.final_target.type
      if name == "value"
        f.puts get_valuetype_documentation(r)
        if target.type == "uml:Enumeration"
          target.generate_enumerations(f)
        end
        next
      elsif (name == "code" && r.redefinesProperty) || (name == "units" && r.default)
        f.puts get_valuetype_documentation(r)
        next
      end
      stereo = r.stereotype!="" ? "`\<\<#{r.stereotype}\>\>`" : ""
      if r.redefinesProperty && r.default
        tbl_rows.append(["#{stereo}{{property(#{name})}}", "`#{r.default}`", "#{r.multiplicity}"])
      else
        tbl_rows.append(["#{stereo}{{property(#{name})}}", "`#{target.name}`", "#{r.multiplicity}"])
      end
    end
 
    unless tbl_rows.empty?
      f.puts "\n#### Value Properties of #{@name}\n\n"   
      f.puts "{{tbl(value-properties-of-#{@name.downcase})}} lists the Value Properties of {{block(#{@name})}}.\n\n"
      f.puts generate_table(
          columns = ["Value Property name", "Value Property type", "Multiplicity"],
          justification = ["-","-",":-:"],
          rows = tbl_rows,
          caption = "Value Properties of #{@name}"
        )

      if !(value_properties.select{|a| !(a.name=="result" && a.redefinesProperty)}.empty?)
        f.puts "\nDescriptions for Value Properties of {{block(#{@name})}}:\n"
      end
      value_properties.each do |r|
        name = r.association_name ? r.association_name : r.name
        target = r.final_target.type    
        if name == "value"
          next
        elsif (r.association_doc || r.documentation || r.target.type.type == "uml:Enumeration") && !r.redefinesProperty
          stereo = r.stereotype!="" ? "`\<\<#{r.stereotype}\>\>`" : ""
          documentation = r.association_doc ? r.association_doc : r.documentation
          f.puts "\n* #{stereo}{{property(#{name})}} \n\n    #{documentation.gsub("\n","\n    ")}\n"
          if r.target.type.type == "uml:Enumeration" && !stereo.include?("deprecated")
            f.puts get_valuetype_documentation(r, 1, name)
            if !@model.generator.enums.include?(target.name)
              r.target.type.generate_enumerations(f, 1)
            end
          end
        end
      end
    end
  end
  
  def generate_associated_property_doc(f, properties, property_stereotype)
    tbl_rows = []   
    properties.each do |r|
      stereo = r.stereotype!="" ? "`\<\<#{r.stereotype}\>\>`" : ""
      name = r.association_name ? r.association_name : r.name
      target = r.final_target.type
      if r.redefinesProperty && r.default
        tbl_rows.append(["#{stereo}{{block(#{r.default})}}","#{r.multiplicity}"])
      elsif r.association_name && (target.name != name || name == "Condition")
        tbl_rows.append(["#{stereo}{{block(#{target.name})}} (organized by {{block(#{name})}})", "#{r.multiplicity}"])
      elsif !r.association_name && target.name != name
        tbl_rows.append(["#{stereo}{{block(#{name})}}", "#{r.multiplicity}"])
      else
        tbl_rows.append(["#{stereo}{{block(#{target.name})}}", "#{r.multiplicity}"])
      end
    end
    f.puts "\n#### #{property_stereotype} Properties of #{@name}\n\n"
    f.puts "{{tbl(#{property_stereotype.downcase}-properties-of-#{@name.downcase})}} lists the #{property_stereotype} Properties of {{block(#{@name})}}.\n\n"
    f.puts generate_table(
      columns = ["#{property_stereotype} Property name", "Multiplicity"],
      justification = [":-",":-:"],
      rows = tbl_rows,
      caption = "#{property_stereotype} Properties of #{@name}"
    )   
    f.puts "\nDescriptions for #{property_stereotype} Properties of {{block(#{@name})}}:\n"
    properties.each do |r|
      name = r.final_target.type.name
      stereo = r.stereotype!='' ? "`\<\<#{r.stereotype}\>\>`" : ''
      target = r.final_target.type
      if ((r.association_doc || target.documentation || r.target.type.type == "uml:Enumeration") && 
          (!r.redefinesProperty || target.type == 'uml:Class'))
        f.puts "\n* #{stereo}{{block(#{name})}} \n\n    #{target.documentation.gsub("\n","\n    ")}\n"
        f.puts "\n    #{r.association_doc.gsub("\n","\n    ")}\n" if r.association_doc!=""
        if !r.association_name && target.name != name && !r.target.type.type == 'uml:Enumeration'
          f.puts "\n    The value of {{block(#{name})}} **MUST** be a `#{target.name}`.\n"
        end
        if r.target.type.type == 'uml:Enumeration' && !r.redefinesProperty && !(r.stereotype && r.stereotype.include?('deprecated'))
          r.target.type.generate_enumerations(f, 1)
        end
      end
    end
  end

  def generate_enumerations(f, num_of_tabs = 0)
    $logger.debug "***** =====> Generating Enumerations for #{@name}"
    tab = "    " * num_of_tabs
    stereo = @stereotype != '' ? "`\<\<#{@stereotype}\>\>` " : ""
    f.puts "\n#{tab}#{stereo}`#{escape_name}` Enumeration:\n\n"
    @literals.each do |lit|
      lit_stereo = lit.stereotype != "" ? "`\<\<#{lit.stereotype}\>\>` " : ""
      f.puts "\n#{tab}* #{lit_stereo}`#{lit.name}` \n\n    #{tab}#{lit.description.gsub("\n","\n    #{tab}")}\n"
    end
    @model.generator.enums << @name
  end
  
  def generate_entrykeys(f)
    $logger.debug "***** =====> Generating Keys for #{@name}"
    f.puts "\n`#{escape_name}` keys:\n"

    @relations.each do |r|
      next if r.name == 'Supertype'
      f.puts "\n* `#{r.name}` \n\n    #{r.documentation.gsub("\n","\n    ")}\n"
      f.puts get_valuetype_documentation(r,1,r.name)
      target = r.final_target.type
      target.generate_enumerations(f,1) if target.type == "uml:Enumeration" && !r.redefinesProperty
    end
  end

  def generate_md(f = STDOUT, parent ='')
    # puts "--- Generating #{@name} #{@stereotype}"
    return if @name =~ /Factory/ || @stereotype =~ /metaclass/ || @visibility != 'public'
    stereotype = has_mtconnect_stereotype? ? "`\<\<#{@stereotype}\>\>`" : ""
    section_name = stereotype+escape_name
    if @is_subtype
      section_type = (@model.name == "Component Types" &&
      parent.name != @relations[0].final_target.type.name) ? "#####" : "####"
      if !model_has_observation_types?
        f.puts "\n#{section_type} #{section_name}\n\n"
        generate_documentation(f)
      end
    elsif @model.name == "Composition Types"
      f.puts "\n### #{section_name}\n\n"
      generate_documentation(f)
      generate_types(f)
    elsif !(@model.name.end_with?('Types') && section_name.end_with?('Result'))
      f.puts "\n### #{section_name}\n\n"
      generate_documentation(f)
      generate_types(f)
    end
  end

  def generate_glossary_docs(f, glossary_type)    
    f.puts generate_glossary_entry(glossary_type)
  end
  
  def generate_profile_docs(f)
    return if @visibility != 'public'
    f.puts "\n### #{@name}\n"
    generate_documentation(f)
  end
  
  def model_has_mtconnect_supertype?
    return (!relations.empty? && 
        @relations[0].name == "Supertype" &&
        @relations[0].final_target.type.name &&
        (@model.name.split(" ")[0] == @relations[0].final_target.type.name ||
        ["Event","Sample","Condition"].include?(@relations[0].final_target.type.name)))
  end

  def model_has_observation_types?
    return (@model.name.include?("Sample") || 
      @model.name.include?("Event") ||
      @model.name.include?("Condition") || 
      @model.name.include?("Interface"))
  end

  def observation_type_has_subtypes?
    return (!@is_subtype &&
        @subtypes.length > 0)
  end

  def type_has_subtypes?(type)
    return (@model.generator.dataitemtypes.has_key?(type.name) &&
      @model.generator.dataitemtypes[type.name].has_key?('subTypes') &&
      !@model.generator.dataitemtypes[type.name]['subTypes'].empty?)
  end

  def update_dataitemtypes_doc(enum)
    enum.literals.each do |lit|
      if @model.generator.dataitemtypes.has_key?(lit.name) && lit.description
        @model.generator.dataitemtypes[lit.name]['documentation'] = lit.description
      end
    end
  end

  def has_mtconnect_stereotype?
    #to be updated
    return /[[:lower:]]/.match(@stereotype[0])
  end
end
