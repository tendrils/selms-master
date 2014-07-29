#!/usr/bin/ruby -w

#selms_path = File.dirname(__FILE__) || '.' 
selms_path = '.' 


$LOAD_PATH.unshift selms_path+'/lib'
$LOAD_PATH.unshift "#{ENV['SELMS_BASE']}/lib" if ENV['SELMS_BASE']

#require 'pp'
require "Action.rb"
require 'Host.rb'
require 'Config.rb'
require 'find'
require 'optparse'
require 'Periodic'
require 'Realtime'
require 'LogStore'
#require 'Daemon'
# options defaults

include Config

RT_SOCKET = '/tmp/selms-rt-fifo'
RT_BUFFER_SIZE = 5000
RUN_TYPE = 'periodic' 
OFFSET = 'offset' 
LOG_DIR = '/logs/HOSTS'
LOG_STORE = 'LogStore'

class RunOutMemory < RuntimeError

end
# process command line options

$options = {   # defaults
           'pre' => nil,
           'post' => nil,
           'lock' => nil,
	   'mail_to' => nil,
	   'mail_from' => "security-alert@auckland.ac.nz",
	   'mail_server' => nil,
 	   'mail_subject' => 'SELMS Periodic Report',
	   'no_mail' => nil,
	   'summ_to' => nil,
	   'one_host' => nil,
	   'log_dir' => nil,
	   'print_code' => nil,
	   'outfile' => nil,
	   'offset' => nil,
	   'no_write_offset' => nil,
           'rt_socket'=> nil,
           'time-hosts' => nil,
           'timeout' => 300,  # 5 minutes timeout
	   'maildomain'=> nil,
	   'hostdomain'=> nil,
     'max_report_recs'=> 1000,
     'max_read_recs'=> nil,
	   'date'=> nil,
     'file' => nil,
     'one_file' => nil,
     'log_type' => nil,
	   'log_store' => LOG_STORE,
     'merge_files' => 'yes',
     'ignore_unk_hosts' => nil,
}

$options.default = 'empty'  # returned for unknown keys 

debug_opts = %w( match hosts host-match gets files code rules-drops rules-ignore rules-alert\
                 rules-warn rules-count rules-incr proc regexp split match-code action)

OptionParser.new { |opts|
  opts.on( '--debug=DEBUG', debug_opts , String) {|val| $options['debug.'+val] = true } 
  opts.on( '-t', '--task=RUN_TYPE', %w( realtime, periodic, daily, weekly, monthly),\
	  String) {|val|   $options['run_type'] = val } 
  opts.on('-o', '--offset=OFFSET', String, "use ARG as offset file suffix" ) { |val|
    $options['offset'] = val }
  opts.on('-O', '--no_write_offset' ) { |val| $options['no_write_offset'] = val }
  opts.on('--no_offset' ) { |val| $options['no_offset'] = val
    $options['no_write_offset'] = val  }
  opts.on('-m', '--mail_to=MAIL_TO', String, "send all mail to ARG") {|val|
    $options['mail_to'] = val}
  opts.on('--mail_from=MAIL_FROM', String, "address to use as from for email") {|val|
    $options['mail_from'] = val}
  opts.on('-L', '--lock=LOCK_FILE', String, "name of lock file") {|val|
    $options['lock'] = val}
  opts.on('--mail_server=MAIL_SERVER', String, "send mail via ARG") {|val|
    $options['mail_server'] = val}
  opts.on('--mail_subject=MAIL_SUBJECT', String, "prefix ARG to mail subject line") {|val|
    $options['mail_subject'] = val}
  opts.on('-M', "Don't send mail to listed contacts") { |val|
    $options['no_mail'] = val}
  opts.on('-s', '--summary=SUMM_TO', String, "send summary to ARG") {|val|
    $options['summ_to'] = val}
  opts.on('-u', '--ignore_unk_hosts', "Ignore hosts that we don't have explicit defs for"){|val|
    $options['ignore_unk_hosts'] = true }
  opts.on('-t', '--time-hosts=TIME_THRES', Integer, "Print processing times for each host, implies host"){|val|
    $options['time-hosts'] = val }
  opts.on('--timeout=TIMEOUT', Integer, "imit of elapsed time to spend on any one file"){|val|
    $options['timeout'] = val }
  opts.on('-h', '--host=HOSTNAME', "run just for this host"){|val|
    $options['one_host'] = val.downcase}
  opts.on('-f', '--file=FILENAME', "run just for this file (daemon, auth, etc)"){|val|
    $options['file'] = val}
  opts.on('--one_file=FILENAME', "run just for this file"){|val|
    $options['one_file'] = val}
  opts.on('--log_type=PLUGIN', "explicitly sepecify plugin -- use with -f"){|val|
    $options['log_type'] = val}
  opts.on('-l', '--log_dir=LOGDIR', String, "Base directory where logs are located"){
    |val| $options['log_dir'] = val}
  opts.on('-S', '--log_store=LOGSTORE', String, "Plugin to traverse log store"){
    |val| $options['log_store'] = val}
  opts.on( '-p', '--pre', String, "run this script before taking action") {
    |val| $options['pre'] = true
  }
  opts.on( '-P','--post', String, "run this script after taking action") {
    |val| $options['post'] = true
  }
  opts.on( '--syntax', String, "just check the syntax of the configuration file") {
   |val| $options['syntax'] = true
 }
  opts.on( '--max_report_recs', String, "give up listing records after this many (default 1000)") {
   |val| $options['max_report_recs'] = val
 }
  opts.on( '--max_read_recs=Max_recs', Integer, "read just this many rececord from each file") {
   |val| $options['max_read_recs'] = val
 }
 opts.on( '--date=DAY', String, "Run for this day") { |val|
    $options['date'] = val
    $options['no_offset'] = true
    $options['no_write_offset'] = true
  }

  begin
    opts.parse!(ARGV)
  rescue  OptionParser::InvalidArgument, OptionParser::MissingArgument,OptionParser::InvalidOption =>e
    puts $!
    puts opts.to_s
    exit 1
  end
  }

  if $options['one_host'] && $options['one_host'] =~ %r!^/(.+)/$!
    begin
      $options['one_host'] = Regexp.new( $1)
    rescue RegexpError
      STDERR.puts "invalid RE supplied for host selection"
      exit 1;
    end
  end  

  if $options['one_file'] && ! $options['one_host']
    STDERR.puts "If you use one_file option you must also use -h (one_host) to give the host name so selms knows which patterns to use"
    exit 1;
  end


# load plugins


%w( plugins lib/plugins ../lib/plugins ).each {|root|
  d = "#{selms_path}/#{root}" 
  next unless File.directory?(d)

  plugins_dir = Dir.new(d) 

  if plugins_dir then
    files = plugins_dir.entries.grep(/.+\.rb$/)
    files.each { |file| 
      require "#{d}/#{file}"
    }
  end
}


if $options['lock'] and File.exists? $options['lock'] 
  STDERR.puts "lock file '#{$options['lock']}' found - selms still running?  exiting! "
  exit
end

hosts = {}
$options['run_type'] =  RUN_TYPE  if $options['run_type'] == 'empty'

  time = Time.new
  if $options['date'] then
    if $options['date'] =~ /(\d+)/ then
      time -=  86400 * $1.to_i;
    end
    $options['no_offset'] = $options['no_write_offset'] = true
  elsif time.hour == 00 && time.min < 10 then  # just after midnight
    time -= 86400 # yesterday -- process the previous days logs
  end
  
  begin
    eval "$log_store  = #{$options['log_store']}.new( '', time )"  # specify root after we have read the config...
  rescue ScriptError=>e
    STDERR.puts "Failed find LogStore class: #{e}"
    exit 10
  rescue StandardError=>e
    STDERR.puts "Failed open LogStore #{e}"
    exit 10
  end  

conf_file = ARGV.shift

abort "No config file given" unless conf_file

abort "can not find file '#{conf_file}'" unless File.exists?( conf_file );

cf_time = File.mtime(conf_file)

parse_config(conf_file, $options['run_type'] )

# up date the options from the config file -- command line overrides

if  $global 
  $global.vars.each { |opt, val|
    $options[opt] ||= val
  }
end



log_root = LOG_DIR
if $options['log_dir'] 
  log_root = $options['log_dir']
else 
  log_root = $global.vars['log_dir'] if $global.vars['log_dir']
end

$log_store.root = log_root

$options.default = nil  # return to default behaviour

# set default options

$options['offset'] ||= OFFSET 
$options['rt_socket'] ||= RT_SOCKET
$options['rt_buffer_size'] ||= RT_BUFFER_SIZE


if $options['pre']
  system( $options['pre'] )
end

begin

  if $options['lock']
    lock = File.open($options['lock'], 'w')
    lock.close
  end


  case $options['run_type']
  when 'periodic' 

    Periodic.new(  $options['syntax'] )
    exit( $errors ) if $options['syntax'] 

  when 'realtime'  
    rt =  Realtime.new( )  # generate object to do realtime scanning
    
    exit conf.errors ? 1 : 0 if $options['syntax'] 

    rt.run_it                    # start it running
    while rt.watch_it do
      
      exit unless rt.re_read_conf
      re_read_conf = false
      put "watch_it exited" 
      
    new_conf = Selms::Config.new(conf_file, run_type )
    
   # cope with change of log socket
    
      if $options['rt_socket']  !=  new_conf.vars['rt_socket'] then
        $options['rt_socket'] =  new_conf.vars['rt_socket'] 
        #        .close
        $logs = LogRecs.new( log_source )
      end
      new_rt = Realtime.new( new_conf )
      
      if new_rt.report.code != rt.report_code or
          new_rt.scan.code != rt.scan_code then  # changes affect RT
        old_rt = rt
        rt = new_rt
      end
    #      end
      if ! rt.thread or ! rt.thread.alive? then
        rt.run_it
      end
      if old_rt && old_rt.thread.alive? then
        old_rt.kill_it    # kill old thread
      end
    end
    
  when 'daily'
    Daily.new
  when 'weekly'
    Weekly.new
  when 'monthly'
    Monthly.new
  end
  
rescue 
  File.unlink $options['lock'] if $options['lock']
  raise
end

File.unlink $options['lock'] if $options['lock']
exit 0;
