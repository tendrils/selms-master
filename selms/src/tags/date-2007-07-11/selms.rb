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

# process command line options

$options = {
	   'mail_to' => nil,
	   'mail_server' => nil,
 	   'mail_subject' => 'SELMS Periodic Report',
	   'no_mail' => nil,
	   'summ_to' => nil,
	   'one_host' => nil,
	   'log_dir' => LOG_DIR,
	   'print_code' => nil,
	   'outfile' => nil,
	   'offset' => nil,
	   'no_write_offset' => nil,
	   'rt_socket'=> nil,
	   'maildomain'=> nil,
	   'hostdomain'=> nil,
	   'max_log_recs'=> nil,
	   'date'=> nil,
	   'log_store' => LOG_STORE,
}

$options.default = 'empty'  # returned for unknown keys 

debug_opts = %w( match hosts gets files code rules-drops rules-ignore rules-alert\
                 rules-warn rules-count rules-incr proc regexp split match-code )

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
  opts.on('-h', '--host=HOSTNAME', "run just for this host"){|val|
    $options['one_host'] = val}
  opts.on('-l', '--log_dir=LOGDIR', String, "Base directory where logs are located"){
    |val| $options['log_dir'] = val}
  opts.on( '--syntax', String, "just check the syntax of the configuration file") {
    |val| $options['syntax'] = true
  }
  opts.on( '--date=DAY', String, "Run for this day") { |val| 
    $options['date'] = val
    $options['no_offset'] = true
    $options['no_write_offset'] = true
  }

  begin
    opts.parse!(ARGV)
  rescue OptionParser::InvalidArgument, OptionParser::MissingArgument
    puts $!
    puts opts.to_s
    exit 1
  end
  }

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
    eval "$log_store  = #{$options['log_store']}.new( \"#{$options['log_dir']}\", time )"
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

$global.vars.each { |opt, val|
  $options[opt] ||= val
}

$options.default = nil  # return to default behaviour

# set default options

$options['offset'] ||= OFFSET 
$options['rt_socket'] ||= RT_SOCKET
$options['rt_buffer_size'] ||= RT_BUFFER_SIZE


case $options['run_type']
when 'periodic' 

  Periodic.new(  $options['syntax'] )
  exit( $errors ) if $options['syntax'] 

when 'realtime'  
  rt =  Realtime.new( $options['syntax'] )  # generate object to do realtime scanning

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
  Daily.new( conf )
when 'weekly'
  Weekly.new( conf )
when 'monthly'
  Monthly.new( conf )
end

exit 0;