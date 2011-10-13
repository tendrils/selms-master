require 'net/protocol'

require 'RunType.rb'
require 'Host.rb'
require 'Config.rb'
require 'Codegen.rb'
require 'find'
#require 'Util'

class Periodic # < RunType

include Codegen

  def add_action_class( key, value)
    @action_classes[key]=value
  end

  def action_class( key)
    @action_classes[key]
  end
  attr_writer :action_classes

# guess at type of host from the files in the log  dir

  def initialize( syntax )

#######
    $run = self
    @action_classes={}
    @counters = {}
#######

    hosts = {}
    host_patterns = {}
  
    start_code( 'periodic', hosts, host_patterns )

    return if syntax  # dont run stuff if it is just a syntax check...

    processed_hosts = {}
    
    # walk the log tree 
    $log_store.traverse do | dir_name, mach|

      priority = -1
      unless host = hosts[mach] then
	      puts "host-match debug:#{mach}" if $options['debug.host-match']
	      host_patterns.each do |name, h |
          puts "    #{priority} #{h.priority}   #{h.pattern}" if $options['debug.host-match']
          if mach.match( h.pattern ) && h.priority > priority then
            puts "        match" if $options['debug.host-match']
            host = hosts[mach] = h.dup
            host.name = mach
            priority = host.priority
          end
        end
#        host = hosts['default'] unless host 
      end

       # if we get here there was no host entry or pattern for this machine

      if ! host then
        Find.prune if $options['ignore_unk_hosts']
      #	puts "#{name} #{dir_name} #{$log_store.type_of_host( dir_name ) }"
        if type = $log_store.type_of_host( dir_name ) then
                if ! hosts[ "default-#{type}"] then
            STDERR.puts "No default definition for #{type}"
            Find.prune
          end
          host = hosts[mach] = hosts[ "default-#{type}"].dup
        else
          h = hosts[ "default"]
          host = hosts[mach] = h.dup if h
        end
        host.name = mach if host
      end

      if ! host then
      	STDERR.puts "no default host definition ignoring host #{mach}"
	      Find.prune
	      next
      end

      if host.ignore then
	      Find.prune
	      next
      end

      if processed_hosts[host] then 
	      processed_hosts[host] += 1
      else
	      processed_hosts[host] = 1
      end

      host.pscan( dir_name, mach )
      Find.prune  unless $options['one_file']

    end

    @action_classes.each{ |key, act_cla|
      act_cla.produce_reports(processed_hosts)
    } 

  end

end
