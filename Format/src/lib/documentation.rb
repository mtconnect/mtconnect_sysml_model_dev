require 'set'

class Documentation
  attr_reader :sections

  class Section
    attr_reader :title, :text

    def initialize(title, text)
      @title, @text = title, text
    end

    def eql?(other)
      @title.eql?(other)
    end

    def hash
      @title.hash
    end

    def <=>(other)
      @title <=> other.title
    end

    def to_s
      "## #{@title}\n\n#{@text}"
    end
  end
  
  def initialize(element)
    @sections = Set.new

    element.xpath('./ownedComment').each do |comment|
      if comment.attributes.include?('body')
        sub = comment.elements.detect { |e| e.name == 'ownedComment' }
        if sub and sub.name == 'ownedComment'
          section = Section.new(comment['body'], sub['body'])
        else
          section = Section.new('Definition', comment['body'])
        end
        @sections.add(section)
      end
    end
  end

  def empty?
    @sections.empty?
  end

  def definition
    d = @sections.detect { |s| s.title == 'Definition' }
    d.text if d
  end

  def to_s
    unless @sections.empty?
      definition || @sections.first.text
    else
      ''
    end
  end
end
