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
  
 
    # define a new class for each host.  The class inheirits from Host and 
    # defines host specific scanning and alerting methods

    start_code( 'periodic' )

    $hosts.each { |name, h| 
      if name =~ /^default/ || ! $options['one_host'] || $options['one_host'] == name then
	make_host_class( h, hosts, 'periodic') 
      end
   }

    $host_patterns.each { |h|
      if  ! $options['one_host'] || $options['one_host'].match(h.pattern)  then
	make_host_class( h, host_patterns, 'periodic' )
      end
    }

    return if syntax  # dont run stuff if it is just a syntax check...

    processed_hosts = {}
    
    # walk the log tree 

    $log_store.traverse { | dir_name, mach|
      unless host = hosts[mach] then
	host_patterns.each { |name, h |
	  if mach.match( h.pattern ) then
	    host = hosts[mach] = h.dup
	    host.name = mach 
	    break
	  end
	} 
      end

      # if we get here there was no host entry or pattern for this machine

      if ! host then
	Find.prune if $options['ignore_unk_hosts']
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
      Find.prune  

    }

    @action_classes.each{ |key, act_cla|
      act_cla.produce_reports(processed_hosts)
    } 

  end

end
