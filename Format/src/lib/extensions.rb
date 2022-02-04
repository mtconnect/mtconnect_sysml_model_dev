$: << File.dirname(__FILE__)

module Extensions
  def xmi_stereotype(e)
    id = e['xmi:id']
    Stereotype.stereotype(id)
  end

  def version_for(stereo)
    if @stereotypes
      st = @stereotypes.detect { |s| s.name == stereo }
      st.version if st and st.respond_to? :version
    end
  end

  def introduced
    if defined? @introduced
      @introduced
    else
      @introduced = version_for('normative')
    end
  end

  def deprecated
    if defined? @deprecated
      @deprecated
    else
      @deprecated = version_for('deprecated')
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
