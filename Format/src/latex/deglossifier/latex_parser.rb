require 'rubygems'
require 'treetop'
require 'set'
require 'memoist'

Treetop.load 'latex'

module Treetop
  module Runtime
    class SyntaxNode
      alias _to_s to_s

      def formatted
        if respond_to? :value
          value
        else
          text_value
        end        
      end

      def to_s
        if respond_to? :value
          return value
        else
          _to_s
        end        
      end
    end
  end
end

class LatexParser
  attr_reader :entries
  
  def parse_glossary(file)
    res = parse(File.read(file))
    unless res
      puts failure_reason
      puts terminal_failures.join("\n")
      exit
    end

    @indexes = Hash.new { |h, k| h[k] = [] }        
    @entries = Hash.new
    @plural = Hash.new
    @singular = Hash.new

    res.elements.each do |e|
      next unless Latex::GlossaryEntry === e

      if e.kind
        e.kind.each do |k|
          @indexes[k] << e
        end
      end

      if e.has_key? :category
        @indexes[e.category.to_s.to_sym] << e
      elsif !e.kind
        @indexes[:term] << e
      end


      name = e.name.to_s
      @entries[name] = e
      @entries[e.name_property.to_s] = e unless e.name_property.to_s.start_with?(/[a-z]/)
      @entries[e.plural.to_s] = e if e.has_key?(:plural)

      if e.name_list.length == 1 and e.has_key?(:plural)
        plural = e.plural.to_s.downcase
        @entries[plural] = e
        
        @singular[plural] = name
        @plural[name] = plural
      end
    end

    puts "Entries: #{@entries.length}"
    @indexes.each do |kind, list|
      puts "  #{kind.inspect}: #{list.count}"
    end
  end

  def plural(word)
    return @plural[word] if @plural.include?(word)
    case word
    when /(o|s|ss|ch|x)$/
      "#{word}es"

    when /y$/
      "#{words.slice(0...-1)}ies"

    else
      "#{word}s"
    end
  end

  def singular(word)
    return @singular[word] if @singular.include?(word)
    case word
    when /(o|s|ss|ch|x)es$/
      word.slice(0...-2)

    when /ies$/
      "#{word.slice(0...-3)}y"
      
    when /s$/
      word.slice(0...-1)

    else
      word
    end
  end

  def entries(m)
    [m, m.to_s.downcase.to_sym].each do |s|
      return @indexes[s] if @indexes.include?(s)
      ms = singular(s.to_s).to_sym
      return @indexes[ms] if @indexes.include?(ms)
      ms = plural(s.to_s).to_sym
      return @indexes[ms] if @indexes.include?(ms)
    end    
  end
  
  def method_missing(m, *args, &block)
    r = entries(m)
    return r if r

    puts "Cannot resovle '#{m}', tried '#{plural(m.to_s)}' and '#{singular(m.to_s)}'"
    super
  end

  def [](key)
    @entries[key]
  end
end

module Latex
  class GlossaryEntry
    extend Memoist
    
    attr_accessor :parent, :elements
    
    def initialize(text, range, elements)
      @elements = elements
    end

    def inspect
      "\#<#{self.class.name}: #{name.inspect} #{keys.inspect}>"
    end

    def name_list
      name_tokens.elements.map(&:value).compact
    end
    memoize :name_list

    def name
      name_list.join(' ')
    end
    memoize :name

    def description
      keys[:description].formatted
    end

    def facet
      if has_key?(:facet)
        return keys[:facet]
      elsif kind_of?(:sample)
        return 'float'
      else
        return 'string'
      end
    end

    def keys
      kys = Hash.new
      properties.elements.map(&:value).compact.each do |k, v|
        kys[k.to_sym] = v
      end
      if !kys.include?(:description) and respond_to? :long_description and
        long_description.respond_to? :value
        kys[:description] = long_description 
      end
      kys
    end
    memoize :keys

    def category
      if keys.include?(:category)
        keys[:category]
      else
        'term'
      end
    end

    def <=>(other)
      self.name <=> other.name
    end

    def deprecated?
      keys.include?(:deprecated)
    end

    def has_key?(key)
      keys.include?(key)
    end

    def name_property
      keys[:name].value.gsub('$', '')
    end

    def kind
      k = self.keys[:kind]
      k = k.value.split(',').map(&:to_sym) if k
      k
    end
    memoize :kind

    def [](key)
      keys[key]
    end

    def kind_of?(k)
      (kind and kind.include?(k))
    end
    
    def method_missing(method, *args, &block)
      if !keys.include?(method)
        puts "Cannot find entry: #{@name} #{keys.inspect}"      
        super
      else
        keys[method]
      end
    end
    
    def dump
      puts "Name: #{name.inspect}"
      puts "Keys: #{keys.inspect}"
    end
    
    def to_s
      "#{name.inspect} -> #{keys.inspect}"
    end
  end
  
  class Property < Treetop::Runtime::SyntaxNode
    def value
      [key.text_value, content]
    end

    def to_s
      value
    end
  end
  
  class Command < Treetop::Runtime::SyntaxNode
    attr_reader :command
    
    def command
      if !defined? @command
        @command = name.value
      end
      @command
    end

    def formatted
      case command
      when 'gls'
        node = $parser[content.value]
        "{#{node.category}:#{node[:name].formatted.strip}}"

      when 'glspl'
        node = $parser[content.value]
        if node[:plural]
          "{#{node.category}:#{node[:plural].formatted.strip}}"
        else
          "{#{node.category}:#{node[:name].formatted.strip}}"
        end
        
      when 'textit'
        "_#{content.formatted}_"

      when 'texttt'
        "@#{content.formatted}@"

      when 'normalfont'
        "#{content.formatted.strip}"

      else
        if content.respond_to?(:formatted) and !content.formatted.empty?
          "*#{command.upcase}:#{content.formatted}*"
        else
          "*#{command.upcase}*"
        end
      end
    end

    def value
      if content.respond_to? :value
        content.value
      else
        command
      end
    end

    def to_s
      value
    end
  end
end
