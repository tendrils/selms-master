#require "plugins/nagiosbase"

class Action

  class Nagios < Action::Base

    def initialize(host, pass, debug = true, port=5667, time_out=20)
      @host = host
      @pass = pass
      @debug = debug
      @port = port
      @time_out = time_out
      @bucket = {}
      @n = nil

      @types = {
          'alert' => 2,
          'warn' => 1,
          'unusual' => 0
      }
    end

    def do_periodic (type, host, file, rec)
      if !host.recs[type + '-Nagios'] then
        host.recs[type + '-Nagios'] = []
      end
      host.recs[type + '-Nagios'] << rec
    end


    def do_realtime (type, host, file, rec)
      data = []
      if @bucket[type] then
        data = @bucket[type]
      else
        data << rec
      end
#pp data

      @n = NagiosBase.new(@host, @pass, @debug, @port, @time_out) unless @n

      data.each { |line|
#puts line
        @n.send(host.name, 'SELMS', @types[type], line)
      }
      @n.close
      @n = nil
#exit
    end
  end

  def produce_reports(processed_hosts)

    # go through the hosts and build reports for each reporting address                                        

    processed_hosts.each { |host, count| # each host we have logs to report for                                       
    # skip unless we have something to report

      next unless host.recs['UNUSUAL-Nagios'].size + host.recs['ALERTL-Nagios'].size +
          host.recs['WARNL-Nagios'].size > 0 || host.count.size > 4;
      @n = Nagios.new(@host, @pass, @debug, @port, @time_out) unless defined @n

      types.keys.each { |type|
        next unless type -~/-Nagios$/
        host.recs[type].each { |r|
          proc, rec = r.split(/\t/)
          @n.send(host.name, proc, result[type], rec)
        }
      }
    }
  end

  public :test
end

if __FILE__ == $0 # someone is running me!
  host = ARGV.shift

  n = NagiosBase.new(host, '2bmshtr', true)
  while gets
    chomp
    (h, r, m) = $_.split(/\s*,\s*/)
    n.send(h, 'SELMS', r.to_i, m)
  end
  n.close
end
