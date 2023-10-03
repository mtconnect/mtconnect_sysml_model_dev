# Add directory to path
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', File.dirname(__FILE__))
require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

$: << File.dirname(__FILE__)
$: << File.join(File.dirname(__FILE__), 'lib')

require 'logger'
require 'optparse'
require 'json'
require 'set'
require 'rexml/document'
require 'rexml/xpath'
require 'nokogiri'
require 'treetop'
require 'generate_documentation'
require 'generate_schema'
require 'generate_portal'
require 'type'
require 'model'
require 'kramdown'
require 'kramdown-math-katex'

Options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: generate.rb [options] [docs]"

  opts.on('-d', '--[no-]debug', 'Debug logging') do |v|
    Options[:debug] = v
  end
  opts.on('-v', '--version VERSION_NUM', 'MTConnect Version') do |ver|
    Options[:version] = ver
  end
  opts.on('-m', '--model MODEL_VERSION', 'Model Version Number') do |ver|
    Options[:model_version] = ver
  end
end
parser.parse!

$logger = Logger.new(STDOUT)
$logger.level = Options[:debug] ? Logger::DEBUG : Logger::INFO 
$logger.formatter = proc do |severity, datetime, progname, msg|
  "#{Time.now} #{severity}: #{msg}\n"
end

unless ARGV.first
  $logger.error "The directive docs must be given"
  $logger.error parser.help
  exit
end

xmi_file = File.join(File.dirname(__FILE__), '..', '..', 'MTConnect SysML Model.xml')
unless File.exist?(xmi_file)
  $logger.error "Model XMI \"MTConnect SysML Model.xml\" not found."
  exit
end

xmi_node = Nokogiri::XML(File.open(xmi_file)).slop!
$namespaces = Hash[xmi_node.namespaces.map { |k, v| [k.split(':').last, v] }]

$mtconnect_version = Options[:version] ? Options[:version] : "X.X"
$dataitemtypes = Hash.new

operations = Set.new(ARGV)

operations.each do |op|
  Type.clear
  Model.clear
  Relation.clear
  
  case op
  when 'docs'
    document_generator = DocumentGenerator.new xmi_node.at('//uml:Model')
    document_generator.generate_all()
    
  when 'schema'
    Glossary = XMIParser.new
    schema_generator = SchemaGenerator.new

  when 'portal'
    portal_generator = PortalGenerator.new xmi_node.at('//uml:Model')
    portal_generator.generate()
  
  else
    $logger.error "Invalid option #{op}"
    $logger.fatal parser.help
  end
end
