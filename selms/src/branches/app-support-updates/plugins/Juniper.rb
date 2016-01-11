

class Juniper < LogFile

  def initialize(name, fn=nil, split_p=nil, head=nil)

    # mib2d: QFABRIC_INTERNAL_SYSLOG: RSNG-ITS-Faculty-Servers-pod1: SNMP_TRAP_LINK_DOWN: [junos@2636.1.1.1.4.61.1 snmp-interface-index="1211630150" admin-status="up(1)" operational-status="down(2)" interface-name="xe-0/0/24"] ifIndex 1211630150, ifAdminStatus up(1), ifOperStatus down(2), ifName xe-0/0/24

    split_p = /^([^:]+): [^:]+: ([^:]+): (-|[^:]+):? .+/ unless split_p

    super(name, fn, split_p  )

    @Tokens = {
        'proc' => [ String, 'options' ],
        'cat'    => [String, 'options'],
    }

    @rc = Record
  end


  class Record < LogFile::Record

    attr_reader  :cat, :proc, :service, :fn

    def initialize(raw=nil, pat=nil, split_p=nil)
      super(raw, pat, split_p)
    end


    def split
      return nil unless @data
      all, @proc, @service, @cat,  data = @data.match( @split_p ).to_a

      if ! all  # split failed
        @orec = @raw
        @proc = 'none'
      else
        @orec = "#{@time} #{@h}: #{@proc}: #{@cat}: '#{@data}'"
      end
    end

  end
end
