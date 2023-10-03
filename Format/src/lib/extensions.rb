$: << File.dirname(__FILE__)

require 'constraint'
require 'stereotype'
require 'documentation'

module Extensions
  def xmi_stereotype(e)
    id = e['xmi:id']
    Stereotype.stereotype(id)
  end

  def get_versions
    @introduced = @deprecated = @updated = nil
    if @stereotypes
      @stereotypes.each do |st|
        case st.name
        when 'normative'
          @introduced = st.introduced if st.respond_to? :introduced
          @introduced = st.version if st.respond_to? :version and @introduced.nil?
          @deprecated = st.deprecated if st.respond_to? :deprecated and @deprecated.nil?
          @updated = st.updated if st.respond_to? :updated

        when 'deprecated'
          @deprecated = st.version if st.respond_to? :version
        end
      end
    end
  end

  def collect_constraints(element)
    element.xpath('./ownedRule').map do |c|
      Constraint.new(c)
    end
  end

  def introduced
    get_versions if not defined? @introduced
    @introduced
  end

  def deprecated
    get_versions if not defined? @deprecated
    @deprecated
  end

  def updated
    get_versions if not defined? @updated
    @updated
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
