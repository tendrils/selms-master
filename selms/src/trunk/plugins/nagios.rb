require "pp"
require "socket"
#require '../Action.rb'
require 'zlib'
require 'dl/import'

module Alarm
  extend DL::Importable
  if RUBY_PLATFORM =~ /darwin/
    so_ext = 'dylib'
  else
    so_ext = 'so.6'
  end
  dlload "libc.#{so_ext}"
  extern "unsigned int alarm(unsigned int)"
end                                                                                

class Nagios 
  include Zlib
  
  def initialize( host, pass, debug = false, port=5667, time_out=20 )
    @host = host
    @port = port
    @password = pass
    @debug = debug
    @time_out = time_out
    @packet_version = 3

    @status = open_socket
  end

  def test( host, pass, debug = false, port=5667, time_out=20 )
    host+pass+debug.to_s+port.to_s+time_out.to_s
  end 
  
    # Open the socket
  def open_socket
    if !( @socket = TCPSocket.new( @host, @port )) then
      raise "OpenProblem"
    end

    # Get 128bit xor key and 4bit timestamp.
    raise "OpenProblem" unless @iv = @socket.read(128)
    raise "OpenProblem" unless @timestamp = @socket.read(4)
    trap("ALRM") {
      @status = 'stale'
    }
    @d = 0
    Alarm.alarm(@time_out)  
    'open'
  end

  def debugit(msg)

    if @debug then 
      puts "# DEBUG #{$$}# #{msg}"
    end
  end

# xor the data (the only type of "encryption" we currently use)
  def myxor( xor_key, str)
 
    xlen = xor_key.length
    str.length.times{ |i| str[i] ^= xor_key[i % xlen]}
    return str
  end

  def send( hostname, service, return_code, status )
    return if hostname == '' || service == '' || return_code == '' || status == ''

    if @status != 'open' 
      close
      @status = open_socket
    end

    # Reset the crc value
    crc = 0
    @d += 1
    
    debugit("Read input: " + [hostname,service,return_code,status].join("\t"))
    
    # Build our packet.
#puts @packet_version, crc, @timestamp, return_code, hostname, service, status
	  tobecrced = [@packet_version, crc, @timestamp, return_code, hostname, service, status].
	  pack("nxx N a4 n a64 a128 a512xx")
    # Get a signature for the packet.
    crc = crc32(tobecrced)
  puts crc
	# Build the final packet with the sig.
    str = [@packet_version, crc, @timestamp, return_code, hostname, service, status].
      pack("nxx N a4 n a64 a128 a512xx")
    
    # Xor the sucker.
    myxor(@iv, str)
    myxor(@password, str)
# puts str

  begin
    @socket.send(str, 0) 
  
  rescue Exception => e
    STDERR.puts "Could not send nagios packet #{@d} #{e}"
    raise "SendError"
  end

    debugit("Sent #{return_code}, #{hostname}, #{service}, #{status} to #{@host}")
  end


  def close
    # Goodbye
    @socket.close
    
    puts "Sent #{@d} packets to #{@host}\n";
  end
end

class Action
  
  class Nagios < Action::Base
    
    def initialize( host, pass, debug = false, port=5667, time_out=20 )
      @host = host
      @pass = pass
      @debug = debug
      @port = port
      @time_out = time_out
      
      types = {
        'ALERT'   => 2,
        'WARN'    => 1,
        'UNUSUAL' => 0
      }
    end
    
    def do_periodic ( type, host, msg, rec=nil )
      if ! host.recs[type + '-Nagios'] then 
	 host.recs[type + '-Nagios'] = []
      end
      host.recs[type + '-Nagios'] <<  ( msg || rec )
    end
  

    def do_realtime ( type, host, msg, rec=nil )
      if defined? @bucket[type] then
        data = @bucket[type]
      else
        data=[]
        data << ( msg || rec ) 
      end
      @n = Nagios.new( @host, @pass, @debug, @port, @time_out) unless @n
      data.each{ |line|
        @n.send( $rt.hostname, types[type], line )
      }
      n.close
    end
  end
  
  def produce_reports( processed_hosts )
    
    # go through the hosts and build reports for each reporting address                                        

    processed_hosts.each { |host, count| # each host we have logs to report for                                       
      # skip unless we have something to report 

      next unless host.recs['UNUSUAL-Nagios'].size + host.recs['ALERTL-Nagios'].size +
                  host.recs['WARNL-Nagios'].size > 0 || host.count.size > 4; 
      @n = Nagios.new( @host, @pass, @debug, @port, @time_out) unless defined @n
      
      types.keys.each { |type|
	next unless type -~ /-Nagios$/
        host.recs[type].each { |r|
          proc, rec = r.split(/\t/)
          @n.send( host.name, proc, result[type], rec)
        }
      }
    }
  end
      public :test
end

if __FILE__ == $0     # someone is running me!
  host = ARGV.shift

  n = Nagios.new(host, '2bmshtr', true)
  while gets
    chomp
    (h, r, m) = $_.split(/\s*,\s*/)
    n.send(h, 'SELMS', r.to_i, m )
  end
  n.close
end
