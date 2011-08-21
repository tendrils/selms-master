require 'Procs.rb'

module Codegen

  def start_code( run_type, hosts, host_patterns )

    # initialise class vars
    
    @debug = false
    @run_type = run_type
    
 
    # define a new class for each host.  The class inheirits from Host and 
    # defines host specific scanning and alerting methods

    $hosts.each { |name, h| 
      if name =~ /^default/ || ! $options['one_host'] ||
           ($options['one_host'].class == Regexp ||$options['one_host'].match(name)) || 
           $options['one_host'] == name then
	make_host_class( h, hosts, @run_type ) 
      end
   }

    $host_patterns.each { |name, h|
      if  ! $options['one_host'] || $options['one_host'].class == Regexp ||
        $options['one_host'].match(h.pattern)  then
	make_host_class( h, host_patterns, @run_type )
      end
    }


  end

# action_body generates code for the actions - alert, warn and report


  def action_body( name, actions )

    pre = @run_type == 'realtime' ? 'rt-' : ''

    pp 'in action_body: ', actions if $options['debug.action']
    code = ''
    init = ''

# generate the action routines ( alert warn report )

    %W( alert warn report ).each { |type|
      next unless a = actions.assoc( "#{pre}#{type}" )
      code += "  def #{type}(rec, file = nil, msg=nil)\n"
      this_action = 'ACTION'
      acc_code = ''
#code << "puts \"#{type}  \#{rec}\"\n"

 # jigrery pokery here to cope with acc (accumulate)  before the action 
 # -- the acc.new needs to know the action   
      a[1].each { |action|
        if action[0] == 'acc' then
          if @run_type == 'realtime' then
            acc_code << "    $bucket[self.name+'-#{type}'] = Accumulator.new(self, '#{type}'," +
			     " #{this_action}, #{action[1]}) " +
                             "unless $bucket[self.name+'-#{type}']\n"
#	    acc_code << "    $bucket[self.name+'-#{type}'] << msg || rec\n"
	    code << "ACC_CODE\n"
          else
            warn( "useless use of accumulate outside realtime processing for host #{name}")
	  end
	else  # it is an action class
          if ! @action_classes[action[0]] then
	          eval "$run.add_action_class('#{action[0]}', Action::#{action[0].capitalize}.new(#{action[1]})) "
          end
	  this_action = "$run.action_class('#{action[0]}')"  
	  if @run_type == 'realtime'
            code << "     if  $bucket[self.name+'-#{type}'] then\n"
#	    code << "       $bucket[self.name+'-#{type}'] << (msg || rec)\n"
	    code << "       $bucket[self.name+'-#{type}'] << ( rec)\n"
	    code << "     else\n"
	  end
          code << '       rec << " - #{msg}"  if msg ' +"\n"
	  code << "       $run.action_class('#{action[0]}').do_#{@run_type}('#{type}', self, file, rec )\n"
	  code << "     end\n" if @run_type == 'realtime'
        end
      }

      if acc_code != ''  # perform the substitutions for the actions
        acc_code.sub!(/ACTION/, this_action)
        code.sub!(/ACC_CODE/, acc_code)
      end
      code << "  end\n\n"
    }
    code
  
  end



  def scanner_body( matches, gen_code )

    @debug = $options['debug.matches']
    code = "mdata = msg = nil\n"
#code << "puts rec.data\n"
    alerts = []
    warns = []
    drops = []
    ignores = []
    others = []
    switches = []

    matches.each { |match|
      pp "match",  match if $options['debug.match']
      match[1].each{ |e|
	case e[0]
	when 'switch':  switches.push( match )
	when 'drop' :   drops.push( match )
	when 'alert' :  alerts.push( match )
	when 'warn' :   warns.push( match )
	when 'ignore' : ignores.push( match )
	when 'count', 'incr', 'proc' : others.push( match )
	else
	  print "codegen error unknown action '#{e[0]}'\n"
	end
      }
    }

    return unless gen_code

    all = []
    all.concat( switches )
    all.concat( drops )
    all.concat( alerts )
    all.concat( warns )
    all.concat( ignores )
    all.concat( others )
    post = ''

    count = 0
    all.each{ |match|
      x = nil
      msg = nil
      count += 1
      print "\nMatch #{count}: " if $options['debug.match']
      pp match if $options['debug.match']
      c = ""
      match[0].each{|cond|
        c += ' && ' unless  c == ''
        case cond[0]
	        when 'incr'
#	  c+= "( incr_check( defined? mdata ? mdata:nil,  #{cond[1]}, #{cond[2]}, '#{cond[3]}' ))"
	          c+= "(msg = incr_check(  mdata,  #{cond[1]}, #{cond[2]}, '#{cond[3]}', rec.utime, rec.count ))"
          when 're'
            c += "( m_data = #{cond[1]}.match(rec.data))"
          when 't_var'
            c += cond[1] =~ /%/ ?
              %Q'count[expand("#{cond[1]}",m_data)].var #{cond[2]}  #{cond[3]} ' :
              %Q'count["#{cond[1]}"].var #{cond[2]}  #{cond[3]} '
          when 't_val'
            if cond[3].class == Integer
              c += "m_data[#{cond[1]}].to_i #{cond[2]}  #{cond[3]} "
            else
	            c += "m_data[#{cond[1]}] #{cond[2]}  '#{cond[3]}' "
            end
          else
            if cond[2] == '=~' || cond[2] == '!~'
              c << "! " if cond[2] == '!~'
              c += "m_data = rec.#{cond[0]}.match(#{cond[1]})"
            else
              c += "rec.#{cond[0]} #{cond[2]} #{cond[1]}"
            end
        end
      }

      ret = ''
      a = ''
      match[1].each { |event|
        a += '      '
        y = 'nil'
        if event[2] then
          a += 'x = ' + (event[2]=~/%/ ? %Q'expand("#{event[2]}", m_data)\n' : "'#{event[2]}'\n")
          a += '      '
          y = 'x'
        end
        if $options["debug.rules-#{event[0]}"] then
          key = "#{event[0]}-#{count}"
          a << "    @count['#{key}'] = Host::SimpleCounter.new( 0, '#{key}') unless @count['#{key}']\n" +
              "     @count['#{key}'].incr(rec.count);\n" if @run_type == 'periodic'
        end
        ret = ''
        case event[0]
        when 'drop', 'ignore'
          ret += "return true\n"
        when 'alert', 'warn'
#        a += "alert( #{y}, rec.fn, rec.orec )\n"
          msg = event[1] ? "'#{event[1]}'" : 'nil';
          a += "#{event[0]}(  rec.orec,  rec.fn, #{msg} )\n"
        when 'switch' 
	        a += "@rule_set = \"_#{event[1]}\"\n"
	        a += "report(\"  ********** switching rule sets to #{event[1]} ******* \")\n"
        when 'warn'
#          a += "warn( #{y}, rec.fn, rec.orec )\n"
          a += "warn(  rec.orec,  rec.fn, msg )\n"
        when 'count'
          a += "@count[x] = Host::SimpleCounter.new( #{event[1]}, #{y}) unless @count[x]\n" +
                "    @count[x].incr(rec.count)\n"
        when 'incr'
          a += "@count[x] = Host::TimeCounter.new( #{event[1]}, #{y}) unless @count[x]\n" +
                "      @count[x].incr(time, rec.count)\n" +
                " puts 'incr count'\n"

        when 'proc'
          a << " Procs.#{event[1]}(" + ((defined? event[2]) ? "x, " :'nil') + "rec.data)\n"
	        post << "    Procs.#{event[1]}(nil, 'host')\n"
        end
      }
      code << "    ##{count}:\n" 
      code << "    if #{c} then\n#{a} #{ret}  end\n"
#code << "puts rec if rec =~ /nrpe/\n"
    }
    return [ code, post ]
  end




  def make_host_class( host, hosts, type )

#STDERR.puts host.name # unless host.actions.length > 0

#pp "Host: #{host.name}", host # if @debug
    action_defs = action_code = action_body( host.name, host.actions )

    sb = {}
    post_code = {}
#pp host

    case type
    when 'periodic'
      host.periodic.each{ |name, matches|
	sb[name], post_code[name] = scanner_body( matches, 1  )
      }
    when 'realtime'
      host.real_time.each{ |name, matches|
	sb[name], post_code[name] = scanner_body( matches, 1  )
      }
    end    

   class_name = host.name.to_s.gsub(/[^a-zA-Z0-9]/, '_') 

   class_name = "RE#{class_name}" if class_name[0] == 95 # an' _'
   class_name.capitalize!
   code = "class #{class_name} < Host\n"
   code <<  "  def initialize( conf, src )\n"
   code <<  "    super(conf, src)\n"
   code <<  "    @scanner = '_default'\n"
   code <<  "  end\n"


   code <<  "#{action_defs}\n"

   sb.each { |name, scanner| 
     code <<  "  def _#{name}( file, rec )\n" 
     code <<  "    return unless file\n" if $run_type == 'periodic' 
     code <<  "    errors = 0\n"
     code <<  "    begin\n"
     code <<  "    #{scanner}\n"
     if $run_type == 'periodic' then
       code <<  "    rescue NoMethodError=>e\n"
       code <<  "      report( e )\n"
       code <<  "      if ( errors += 1 ) > 10 then\n"
       code <<  "        report( \"Too many errors -- giving up!\"  )\n"
       code <<  "        return nil\n"
       code <<  "      end\n"
       code <<  "    end\n"
       code <<  "     report( rec.orec, rec.fn )\n"
     else
       code <<  "    end\n"
     end
     code <<  "  return true\n"
     code <<  "  end\n"
     code <<  "  def _post_#{name}\n"
     pc = {}
     post_code[name].each {|p|
       next unless p
       proc = p.match(/Proc.(\w+)/).to_a[1]
       if p
      	 next if pc[p] # already have this one
      	 pc[p] = 1
       end
       code <<  host.recs['post'] = p
     }
     code <<  "  end\n"
   }

   code <<  "end\n"
     
   code <<  "hosts[host.name] = #{class_name}.new( host, code )\n"
   
#       puts host.name
#       puts  code
#puts $options['one_host'], host.name
   if $options['debug.code'] || $options['debug.match-code'] then
     if ! $options['one_host'] ||  $options['one_host'].class == Regexp || 
          $options['one_host'] == host.name ||
	 ( host.pattern && $options['one_host'].match(  host.pattern ) ) then
       puts host.name
       puts code
     end
   end
#puts code
   begin
     eval code
   rescue SyntaxError
     errs = {}
     $!.to_s.split(/\n/).each { |line|
       all, n, msg = line.match(/\(eval\):(\d+):(.*)/).to_a
       errs[n.to_i] = msg
     }
     l = 1
     code.split( /\n/ ).each { |line|
       puts "#{l}: #{line}"
       puts ">>>>> #{errs[l]}" if errs[l]
       l +=1;
     }
   end
#pp hosts[host.name].class,  hosts[host.name].class.instance_methods
 end
end
