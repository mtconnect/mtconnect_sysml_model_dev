
class Stereotype
  @@stereotypes = Hash.new { |h, k| h[k] = [] }

  def self.clear
    @@stereotypes.clear
  end

  def self.stereotype(id)
    @@stereotypes[id] if @@stereotypes.include?(id)
  end

  attr_reader :name, :id

  def initialize(xmi)
    attr = xmi.attributes.to_a.detect { |k, v| k.start_with?('base_') }
    @id = attr[1].value
    @name = xmi.name
    xmi.attributes.each do |k, v|
      if k != 'id'
        instance_variable_set("@#{k}", v.value)
        self.class.attr_reader(k.to_sym)
      end
    end

    @@stereotypes[@id] << self
  end

  def to_s
    "<<#{@name}>>"
  end

  def inspect
    to_s
  end
  
end
