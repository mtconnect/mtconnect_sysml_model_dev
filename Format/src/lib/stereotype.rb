
class Stereotype
  @@stereotypes = Hash.new

  def self.add_stereotype(s)
    unless @@stereotypes[s.profile]
      @@stereotypes[s.profile] = Hash.new { |h, k| h[k] = [] }              
    end
    @@stereotypes[s.profile][s.id] << s
  end

  def self.collect_stereotypes(xmi)
    xmi.document.root.elements.each do |m|
      unless m.namespace
        puts "No namespace found for #{m.node_name} at line #{m.line}"
        next
      end
      
      profile = case m.namespace.prefix
                when 'Profile'
                  :mtc
                  
                when 'MD_Customization_for_SysML__additional_stereotypes'
                  :sysml
                end
      if profile
        Stereotype.new(m, profile)
      end
    end
  end

  def self.stereotypes(profile)
    @@stereotypes[profile]
  end

  def self.clear
    @@stereotypes.clear
  end

  def self.stereotype(id, profile = :mtc)
    @@stereotypes[profile][id] if @@stereotypes.include?(profile) and @@stereotypes[profile].include?(id)
  end

  attr_reader :name, :id, :profile, :tags

  def initialize(xmi, profile)
    attr = xmi.attributes.to_a.detect { |k, v| k.start_with?('base_') }
    
    @id = attr[1].value
    @name = xmi.name
    if @name == 'hasFormatSpecificRepresentation'
      @display = 'representations'
    else
      @display = @name
    end
    @profile = profile
    @tags = Hash.new { |h, k| h[k] = [] } 

    xmi.attributes.each do |k, v|
      if k != 'id' and !k.start_with?('base_')
        @tags[k] = v.value
        instance_variable_set("@#{k}", v.value)
        self.class.attr_reader(k.to_sym)
      end
    end

    xmi.element_children.each do |e|
      @tags[e.name] = e.text
    end

    @tags.each do |k, v|
      instance_variable_set("@#{k}", v)
      self.class.attr_reader(k.to_sym)
    end

    self.class.add_stereotype(self)
  end

  def to_s
    "<<#{@display}>>"
  end

  def html
    "&lt;&lt;#{@display}&gt;&gt;"
  end

  def inspect
    to_s
  end
  
end
