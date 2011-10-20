class LogFile

  GulpTokens = {
      'guser' =>  [String],
      'type' => [String],
      'saddr' => [String],
      'status' => [String],
      'shost'  => [String],
      'service' => [String],
      'extra' => [String],
      'tag'  => [String],
  }
  
  class Snare::Gulp < Snare
    def initialize(name=nil, fn=nil )
      super(name, fn)
      @Tokens.merge!(GulpTokens)
      @rc = Record
      @@strings ||= {
          "Success Audit" => "Success",
          "Failure Audit" => "Failure",
          "" => "",
      }
    end

    class Record < Snare::Record
      attr_reader :type, :guser, :status, :saddr, :shost, :service, :extra, :tag

      def split
        super
        # do stuff with data

#        field ={}
#        data.sub(/(\[A-Z][^:]+):\s(\S+)/) {|m| field[m[1]] = m[2]}

        case @eventid
          when 680
#Logon attempt by: MICROSOFT_AUTHENTICATION_PACKAGE_V1_0 Logon account: wgai002    Source Workstation:313D104WGAI002    Error Code: 0xC000006A        1839389
            state, user, saddr =
              $data.match(/Logon Account:\s+(\S+)\s+Source Workstation:\s*(\S+)/).captures
          when 673
# Service Ticket Request:     User Name: rbal055@AD.EC.AUCKLAND.AC.NZ    User Domain: AD.EC.AUCKLAND.AC.NZ
# Service Name: rbal055     Service ID: -     Ticket Options: 0x800000  Ticket Encryption Type: -
# Client Address: 130.216.100.53     Failure Code: 0x1B     Logon GUID: - Transited Services: -        1850366
            @guser, @extra, $saddr =
              $data.match(/User Name:\s+(\S+)@(\S).*\s+Client Address:\s*(\S+)/).captures
          when 4768, 4769, 4770, 6424, 6425  # kerberos
# A Kerberos authentication ticket (TGT) was requested.
# Account Information:   Account Name:  sshi052@AD.EC.AUCKLAND.AC.NZ   Account Domain:  AD.EC.AUCKLAND.AC.NZ   Logon GUID:  {...}
# Service Information:   Service Name:  FULCRUM$   Service ID:  S-.......
# Network Information:   Client Address:  ::ffff:130.216.249.41   Client Port:  4648
#Additional Information:   Ticket Options:  0x40810000   Ticket Encryption Type: 0x17   Failure Code:  0x0   Transited Services: -


            @type = @eventid == 4770 ? "Renew" : "Auth"
            if( m =  @data.match(/Account Name:\s+ ([^@ ]+)\S*\s+Account Domain:\s+(\S+)\s+(?:Logon ID:\s+(0x9\S+))?/) )
              @guser, @extra, @saddr, @tag = m.captures if m
            else
              return
            end
          when 4648
# A logon was attempted using explicit credentials.
#Additional Information: localhost    Process Information:   Process ID:  0x200   Process Name:  C:\Windows\System32\lsass.exe
#Network Information:   Network Address: 130.216.12.42   Port:   22380
            @type = 'Log on'
            @guser, @extra, @saddr = @data.match(/Network Address: (\S+)/).captures
          when 4634
#An account was logged off.
#Subject:   Security ID:  S-1-5-21-614565923-1027956908-3001582966-27992   Account Name:  SCCMGRPRD03$   Account Domain:  UOA   Logon ID:  0x520bc4b1    Logon Type:   3
            @tag = data.match(/Logon ID:  0x([a-z0-9]+)/).captures
            @type = 'Log off'
          else
            return
        end
        @shost = "AD-#{@h}"
      end
    end

  end

  class Base::Gulp < Base
    def initialize(name=nil, fn=nil )
      super(name, fn)
      @Tokens.merge!(GulpTokens)
      @rc = Record
    end

    class Record < Base::Record
      attr_reader :type, :guser, :status, :saddr, :shost, :service, :extra, :tag

      def split
        super
        if @proc == 'sshd'
          case @data
            when /^/
            else

          end
        elsif @proc == 'cosignd'
          @shost =  'COSIGN'
          @guser, @extra, @saddr, @servic = rest.match( / REGISTER (\S+) \S+ ([.0-9]+) (\S+)/).captures
          @status = 'Success'
          @type = 'Renew'
        elsif @proc == 'cgi.c'
          @shost =  'COSIGN'
          @saddr, rest = @data.match( /\[([.0-9]+)\] (.+)/ ).captures
          if (@guser = rest.match( /^Successfully loaded a remember-me session for (\S+)\// ).captures)
            @status = 'Success'
            @type = 'Authenticate'
          elsif rest.match(/^Username and\/or password incorrect/ )
            @status = 'Failure'
            @type = 'Authenticate'
          end
        end
        # do stuff with data
      end
    end
  end

  class Weblogic::Gulp < Weblogic
    def initialize(name=nil, fn=nil )
      super(name, fn)
      @Tokens.merge!(GulpTokens)
      @rc = Record
    end

    class Record < Weblogic::Record
      attr_reader :type, :guser, :status, :saddr, :shost, :service, :extra, :tag

      def split
        super
        # do stuff with data
        if m =  @data.match(/^(\d+) .+ Relying party request: ([^,]+), User: ([^,]+), IP Address: ([0-9.]+)/)
          @service, @guser, @saddr = m.captures
          @service = nil if @service == "The University of Auckland"
          @status = 'Success'
          @type = 'auth';
        elsif m = @data.match( /User authentication for (\S+) failed$/).to_a
          @guser = m[1]
          @status = 'Failure'
          @type = 'auth';
        end
      end
    end

  end

end



class Action

  class Gulp < Base

    def do_periodic (type, host, rec, msg)
      r = host.recs[type] ||= []
      r << [rec.guser, rec.saddr, rec.shost, rec.service, rec.extra, rec.tag].join("\t")
    end


    def produce_reports(processed_hosts)
      pp processed_hosts
    end

  end
end

