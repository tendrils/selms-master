require 'net/protocol'

require 'RunType.rb'
require 'Host.rb'
require 'Config.rb'
require 'Codegen.rb'
require 'find'
require 'benchmark.rb'
require 'timeout'

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

    @hosts = {}
    @host_patterns = {}

    start_code( 'periodic', @hosts, @host_patterns )

#pp @hosts

    return if syntax  # dont run stuff if it is just a syntax check...

    @processed_hosts = {}

    # walk the log tree 
      $log_store.traverse do | dir_name, mach|
        begin
	  process_host( dir_name, mach )
        rescue RunOutMemory
          @action_classes.each{ |key, act_cla|
            act_cla.produce_reports(@processed_hosts)
          }
          @processed_hosts.keys.each{|host| @processed_hosts.delete(host) }
#	rescue =>e
#	  STDERR.puts "something failed for #{dir_name}: #{e} \n" 
        end

      end

    @action_classes.each{ |key, act_cla|
      act_cla.produce_reports(@processed_hosts)
    } 

  end

  def process_host (dir_name, mach)
    priority = -1

    unless host = @hosts[mach] then
      puts "host-match debug:#{mach}" if $options['debug.host-match']
      @host_patterns.each { |name, h|
        puts "    #{priority} #{h.priority}   #{h.pattern}" if $options['debug.host-match']
        if mach.match(h.pattern) && h.priority > priority then
          puts "        match" if $options['debug.host-match']
          host = @hosts[mach] = h.dup
          host.name = mach
          priority = host.priority
        end
      }
#        host = hosts['default'] unless host 
    end

    # if we get here there was no host entry or pattern for this machine

    if !host 
      Find.prune if $options['ignore_unk_hosts']
#	puts "#{name} #{dir_name} #{$log_store.type_of_host( dir_name ) }"
      if type = $log_store.type_of_host(dir_name) then
        if !@hosts["default-#{type}"] then
          STDERR.puts "No default definition for #{type}"
          Find.prune
        end
        host = @hosts[mach] = @hosts["default-#{type}"].dup
      else
        h = @hosts["default"]
        host = @hosts[mach] = h.dup if h
      end
      host.name = mach if host
    end

    if !host then
      STDERR.puts "no default host definition ignoring host #{mach}"
      Find.prune
      next
    end


    if host.ignore then
      Find.prune
      next
    end
    if @processed_hosts[host] then
      @processed_hosts[host] += 1
    else
      @processed_hosts[host] = 1
    end
    t = Benchmark.measure(mach) { host.pscan(dir_name, mach) }
    STDERR.printf "%-30s: real %5.2f total cpu %5.2f ratio %5.3f threshold %d\n",
                  t.label, t.real, t.total, t.total/t.real, $options['time-hosts'] if $options['time-hosts'] and t.real > $options['time-hosts']
    if  t.real/t.total < 0.1 # it is thrashing!
      STDERR.printf "Run out of memory %-20s: real %5.2f total cpu %5.2f ratio %5.3f\n",
                    t.label, t.real, t.total, t.real/t.total
      raise RunOutMemory
    end
    Find.prune unless $options['one_file']
  end

end
