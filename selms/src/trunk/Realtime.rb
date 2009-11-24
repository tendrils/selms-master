require 'pp'

require 'RunType.rb'
require 'Host.rb'
require 'Codegen.rb'
require 'Config.rb'
require 'LogFile.rb'

class Realtime
include Codegen

  def add_action_class( key, value)
    @action_classes[key]=value
  end

  def action_class( key)
    @action_classes[key]
  end

  attr_writer :action_classes
  attr_reader :thread, :re_read_conf

  def initialize()
  
#######
    $run = self
    @action_classes={}
    @hosts = {}
    @buckets = {}
    @counters = {}
    @host_patterns = {}
#######

   # define a new class for each host.  The class inheirits from Host and 
    # defines host specific scanning and alerting methods

    @thread = false
    $threads = []
    @re_read_conf = false

    # define a new class for each host.  The class inheirits from Host and 
    # defines host specific scanning and alerting methods

    start_code( 'realtime', @hosts, @host_patterns )
  end


  # start a thread that reads the pipe and then passes the record
  # to the approriate host scanner

  def run_it 
#    @thread = Thread.new { 
      files = {}
      def_logf = LogFile.new( 'default',  nil )
      File.open( $options['rt_socket'], 'r' ) { |logs|
	begin
#puts "getting data\n";
	while logs.gets
#	  all, utime, time, hn, record = $_.match(Host::LOG_HEAD).to_a
          hn = $log_store.extract_rt_host( $_ )
#puts hn
          hn.sub!(/\.#{$options['hostdomain']}$/o, '') if $options['hostdomain']
#	  pp rec if $options['debug.split']

#	  hn = h.sub(/\.#{$options['hostdomain']}$/o, '') if $options['hostdomain']

	  next if $options['one_host'] && $options['one_host'] != hn	  

	  unless host = @hosts[hn] then
	    @host_patterns.each { |name, h |
		if hn.match( h.pattern ) then
		  host = @hosts[hn] = h.dup
		  host.name = hn
 
		  break
		end
	      } 
            end
	  next unless host
	  
          unless files[hn]
            if f = (  host.file['all']  ) then
              files[hn] = f.class != Regexp ? f : LogFile.new( @file['all'] ) 
            end
          end
          
	  rec = files[hn]['logtype'].gets( nil, $_)
#          rec.split

	  pp rec if $options['debug.split']
#          host.scanner( '', time, proc, facility, level, record, orec )
puts rec.orec
           host.send host.rule_set, 'TEST', rec 
# pp ">>>>",  host.rule_set         
	  
	end
	rescue StandardError => e
	  puts "\n", e.to_str
	  puts e.backtrace.join("\n")
	end
      }

  end

  def watch_it
    mins = 0

    # every minute look to see if child is still running, if not then restart it
    # every 5 minutes check to see if config file has changed if it has then
    # reread the config file and check to see if anything affecting rt has changed.
    # If so then assign the running thread to old_r and the new one to rt
    # which will started by the check to make sure that the current thread is alive
    # the old thread is then killed

    # to do:  add more checking!

    re_read_conf = false

    Signal.trap('HUP') {
      @re_read_conf = true
      Process.kill('ALRM', 0)
    }
    
    #  $logs = LogRecs.new( $options['rt_socket'], $options['rt_buffer_size'])
    
    while true do # loop every minute
      
      sleep(60)
      return true if re_read_conf

      time = Time.now
      
      $bucket.each { |type, bucket|
	$bucket.delete(type) if bucket.check(time) == 0
      }

    end
  end

 def kill_it
   @thread.kill
 end

end
