module MarkdownMerger

  #Flattens the input file command recursively
  def self.recurse_input_files(md)
    md.scan(/\{\{input\(([^\)]+)\)\}\}/) do |s|
      input_cmd = "{{input(#{$1})}}"
      input_md = File.read(File.join(MarkdownModel.directory, $1))
      md = md.gsub(input_cmd,input_md)
    end
    return md.match(/\{\{input\(([^\)]+)\)\}\}/) ? self.recurse_input_files(md) : md
  end

  def self.flatten(markdown_model)
    main_file = File.join(markdown_model.directory,'main.md')
    main_md = File.read(main_file)
    File.write(File.join(markdown_model.directory,'main_flattened.md'), self.recurse_input_files(main_md))
  end
end