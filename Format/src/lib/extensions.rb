$: << File.dirname(__FILE__)

module Extensions
  def xmi_stereotype(e)
    id = e['xmi:id']
    Stereotype.stereotype(id)
  end

  def introduced
    if @stereotypes
      intro = @stereotypes.detect { |s| s.name == 'normative' }
      intro.version if intro and intro.respond_to? :version
    end
  end

  def deprecated
    if @stereotypes
      intro = @stereotypes.detect { |s| s.name == 'deprecated' }
      intro.version if intro and intro.respond_to? :version
    end
  end

  def xmi_documentation(e)
    recurse = lambda { |v| [ v['body'], v.xpath('./ownedComment').map { |c| [ c['body'], recurse.call(c) ] } ] }
    e.xpath('./ownedComment').map do |c1|      
      recurse.call(c1)
    end.flatten.compact.join("\n\n")
  end

  def get_multiplicity(r)
    lower = upper = '1'
    if r.at('upperValue')
      upper = r.at('upperValue')['value']    
      upper = '0' unless upper
    end
    
    if r.at('lowerValue')
      lower = r.at('lowerValue')['value']
      lower = '0' unless lower
    end


    # $logger.debug "  Multiplicity for #{r.to_s}: #{lower} #{upper}"

    [lower == upper ? upper : "#{lower}..#{upper}",
     optional = lower == '0']
  end
end
