$: << File.dirname(__FILE__)

require 'constraint'
require 'stereotype'
require 'documentation'

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

  def collect_constraints(element)
    element.xpath('./ownedRule').map do |c|
      Constraint.new(c)
    end
  end

  def introduced
    return @introduced if defined? @introduced
    @introduced = version_for('normative')
  end

  def deprecated
    return @deprecated if defined? @deprecated
    @deprecated = version_for('deprecated')
  end

  def informative
    return @informative if defined? @informative
    @informative = @stereotypes.detect { |s| s.name == 'informative' } if @stereotypes
  end
  
  def xmi_documentation(e)
    Documentation.new(e)
  end

  def get_multiplicity(r)
    lower = upper = '1'
    if u = r.at('upperValue')
      upper = u['value']
      upper = '0' unless upper
    end

    if l = r.at('lowerValue')
      lower = l['value']
      lower = '0' unless lower
    end

    # $logger.debug "  Multiplicity for #{r.to_s}: #{lower} #{upper}"
    [lower == upper ? upper : "#{lower}..#{upper}", lower == '0']
  end
end
