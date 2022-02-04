require 'schema/schema'
require 'schema/xmi_parser'

class SchemaGenerator

  attr_reader :msd_files
  
  def initialize
    @msd_files = [File.join(File.dirname(__FILE__), '..', 'schemas', 'msd','MTConnectAssets.msd'),
      File.join(File.dirname(__FILE__), '..', 'schemas', 'msd','MTConnectDevices.msd'),
      File.join(File.dirname(__FILE__), '..', 'schemas', 'msd','MTConnectStreams.msd'),
      File.join(File.dirname(__FILE__), '..', 'schemas', 'msd','MTConnectError.msd')
    ]
    generate_all()
  end

  def generate_all
    @msd_files.each do |file|
      puts "Parsing schema for #{file}"
      schema = Schema.new File.read(file)
    
      %w{1.0 1.1}.each do |version|
        puts "  Generating schema for #{file} #{version}"
        doc = schema.generate_xsd(version)
        ver = "_#{version}" if version != '1.1'
        out = File.join(File.dirname(__FILE__), '..', 'schemas', "#{File.basename(file, '.msd')}_#{schema.version}#{ver}.xsd")
        puts "    Writing schema document: #{out}"
        File.open(out, 'w') { |f| doc.write(f, 2) }
      end
    end
  end
end