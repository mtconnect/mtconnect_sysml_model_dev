

class LazyPointer
  attr_reader :obj, :id
  
  @@pointers = []
  @@objects = Hash.new

  def self.clear
    @@pointers.clear
    @@objects.clear
  end
  
  def self.resolve
    @@pointers.each do |o|
      o.resolve
    end
  end

  def self.register(id, obj)
    @@objects[id] = obj
  end
  
  def _type
    @type
  end
  
  def initialize(obj)
    @id = @obj = nil
    @lazy_lambdas = []
    @unresolved = nil
    
    case obj
    when String
      @id = obj
      @obj = @@objects[@id]
      @@pointers << self unless @obj
      
      raise "ID required when String: #{@id.inspect}" if @id.nil? or @id.empty?
      
    when Type
      @obj = obj
      @id = @obj.id
      
    else
      raise "Pointer created for unknown type: #{obj.class} '#{@tid}' '#{@type}'"
    end
  end

  def eval_lambda(target, block)
    target = @obj unless target
    target.instance_eval(&block)
  end
  
  def lazy(target = nil, &block)
    if @obj
      eval_lambda(target, block)
    else
      @lazy_lambdas << [target, block]
    end
  end

  def unresolved(target, &block)
    @unresolved = [target, block]
  end
  
  def resolved?
    !@obj.nil?
  end
  
  def resolve
    unless @obj
      @obj = @@objects[@id]
      if @obj
        @lazy_lambdas.each do |target, block|
          eval_lambda(target, block)
        end
      else
        if @unresolved
          eval_lambda(*@unresolved)
        else
          $logger.warn "Cannot find object for #{@id}"
        end
      end
    end
    
    !@obj.nil?
  end
  
  def method_missing(m, *args, &block)
    if @obj.nil?
      $logger.warn "!!! Calling #{m} on unresolved object #{@id}"
    else
      @obj.send(m, *args, &block)
    end
  end    
end
