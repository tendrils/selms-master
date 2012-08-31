require 'pp'
require 'Parser.rb'
require 'Codegen.rb'
require 'Procs.rb'

module Config

# parse a Selms config file and produce an internal representation that
# the other components of Selms can use. The parser is a recursive 
# descent one which classes representing the structures in the 
# configuration file.

# the Config class represents the whole config

  LEVELS = {
      'emerg' => 0, # /* system is unusable               */
      'alert' => 1, # /* action must be taken immediately */
      'crit' => 2, # /* critical conditions              */
      'err' => 3, # /* error conditions                 */
      'warning' => 4, # /* warning conditions               */
      'notice' => 5, # /* normal but significant condition */
      'info' => 6, # /* informational                    */
      'debug' => 7 # /* debug-level messages             */
  }

  OPS = {
      '==' => 'both',
      '===' => 'both',
      '>' => 'both',
      '<' => 'both',
      '>=' => 'both',
      '<=' => 'both',
      '==' => 'both',
      '!=' => 'both',
      '=~' => 're',
      '!~' => 're',
  }
  Optional = true
  EmailRE = /^([-a-z0-9+_.]+(?:@[a-z0-9.]+)?)/


  include Parser

  def parse_config(conf_file, options)
    $services = {};
    $hosts = {};
    $run_type = options
    $global = nil

    $host_patterns = {};
    $errors = 0

    return nil unless conf_file;

    $file = conf_file

    setup(conf_file)

      # config file is a series of sections

    while  expect('[', "Start of section i.e. '['")
      head = SectionHead.new

      case head.kind
        when 'global'
          if $global then
            error("only one global section") unless @@included_from.size > 0
            tmp = Global.new(head)
          else
            $global = Global.new(head)
	    $services = $global.services if $global.services.size > 0
          end
        when 'service'
          if $services[head.name] then
            warn("multiple defintions of service '#{head.name}' last will be used")
          end
          $services[head.name] = HostService.new(head)
        when 'host', 'app'
          if $hosts[head.name] then
            warn("multiple defintions of host '#{head.name}' last will be used")
          end
          $hosts[head.name] = HostService.new(head)
          if $hosts[head.name].pattern then
            if $host_patterns[head.name] then
              warn("multiple defintions of host '#{head.name}' last will be used")
            end
            $host_patterns[head.name] = $hosts[head.name]
            $hosts.delete(head.name);
          end
        else
          error("can't have section '#{head.kind}' in the main section")
          recover('}');
      end
    end
    @errors = reset_errors # get the error count from the parser...

  end

# the configuration file is composed of a series of sections -- 
# each section has a heading enclosed in [ ] and a body enclosed
# in { }

# the section head starts with a 'type' and some tyes require that the 
# 'type' be followed by a 'name'

  class SectionHead
    include Parser
    attr_reader :kind, :name, :sectionstart, :options
    attr_writer :name

    def initialize

      @sectionstart = lineno
      @options = false

        # we have the start of a section
      if ! (@kind = expect(/(\w+)/, "section type(word)", SAME_LINE)) then
        error("Could not find valid section type this section " +
                  "will be skipped")
        recover('}', SAME_LINE)
      else
        @kind.downcase!

        if re = expect('re', '', ANYWHERE, OPTIONAL) then
          begin
            @name = @re
          rescue
            error("#{$!}")
            @errors = true
          end
        else
          @name = expect(/^([^, :\]]+)/, "section name",
                         SAME_LINE, 'Optional')
          @name.downcase! if @name
        end

        unless @options = expect(/^:/, nil, SAME_LINE, OPTIONAL) then
          unless expect(/^\]/, "] ending section header or : <options>", SAME_LINE) then
            error("Skipping to start of next section")
            recover(/^\s*\[/)
            return nil
          end
        end
      end
    end
  end # class section head

# trivial container class

  class C
    attr_reader :v
    attr_writer :v

    def initialize (val)
      @v = val
    end
  end

  class MyList < Array

    def initialize(values=nil)
      if values then
        super(values)
      else
        super()
      end
    end

# take two sets of event-action lists
# first: remove those not relevant to this run from one
# second merge in any relvant items from two

    def merge_actions(two, run_type)

      if run_type == 'realtime' then
        self.delete_if { |x| x[0] !~ /^rt-/ }
      else
        self.delete_if { |x| x[0] =~ /^rt-/ }
      end

      two.each { |set|
        actions = set[1]
        event = set[0]
        rt = event =~ /^rt-/
        if run_type == 'realtime' then
          next unless rt
        else
          next if rt
        end
        if !self.assoc(event) then
          self.push(set)
        end
      }
    end


    def <<(array)
      array.each { |a| self.push(a) }
    end
  end # MyList

  class Section
    include Parser
    attr_reader :errors, :kind, :name, :sectionstart

    def initialize(head, process_subsections=true)

      @kind = head.kind unless defined? @kind
      @name = head.name
      @sectionstart = head.sectionstart
      @errors = 0
# puts "Section #{self.class}: #{head.kind} #{head.name}"
      get_options if head.options

      if !expect('{') then
        error("Skipping to start of next section")
        recover('[')
        return nil
      end

      return unless process_subsections

      while (tok = nextT) && tok != '}'
        if tok == '[' then

          head = SectionHead.new
          if ! (details = sub_sections(head.kind)) then
            error("section #{head.kind} not valid here -- " +
                      "Have you missed a brace on previous section?")
            recover('}')
          else
            case details[0]
              when 'name'
                if !defined? head.name then
                  error("section #{head.kind} must have a name part")
                end
              when 'optional'
                head.name = 'default' unless head.name
            end

            if details[5] then
              s = details[1].new(head, details[3], details[4], details[5])
            elsif details[4] then
              s = details[1].new(head, details[3], details[4])
            elsif details[3] then
              s = details[1].new(head, details[3])
            else
              s = details[1].new(head)
            end

            case details[2].class.to_s
              when 'Hash'
                    if defined? s.item then
                      details[2].merge!(s.items)
                    else
                      details[2][s.name] = s
                    end
              when 'Array'
                    if defined? s.items then
                      details[2] << s.items
                    else
                      details[2] << s
                    end
              when 'Config::MyList'
                    details[2] << s.items
              else
                error("internal error -- " +
                          "bad class #{details[2].class.to_s} for section")
                @errors = true;
            end
            @errors ||= s.errors # propogate errors upwards
          end
        else
          specificItem(tok)
        end
      end # have the final brace
    end

    def get_options
      error("extraneous input in header for section #{@kind}")
      error("Skipping to start of next section")
      recover(/^\s*\[/)
      return nil
    end

    def sub_sections(name)
      nil
    end
  end # Section

  class Global < Section
    include Parser
    attr_reader :actions, :vars, :services, :hosts

    def initialize(head)
      @vars = {}
      @services = {};
      @actions = MyList.new
      return super(head)
    end

    def sub_sections(kind)
      {'actions' => ['name', ActionList, @actions],
	'service'     => ['name', HostService, ($global ? @services : $services) ]
#	'service'     => ['name', HostService, $services ]
      }[kind]
    end


    def specificItem(first_token)

      if first_token =~ /\w+/ then
        if expect('=') then
          if $options[first_token] == 'empty' then
            error("#{first_token} is not a known option")
            rest_of_line
          else
            rol = rest_of_line
            @vars[first_token] = (rol =~ /^\s*(\d+)\s*$/) ? $1.to_i : rol
          end
        else
          rest_of_line
        end
      else
        @errors = true
        error("expecting a vaiable name");
        rest_of_line;
      end
    end
  end

  class HostService < Section
    include Parser

    attr_reader :services, :converted, :actions, :patterns, :real_time, :merge_files,
                :periodic, :file, :def_email, :sms, :page, :ignore, :pattern, :logtype,
                :priority, :process_time_limit
    attr_writer :converted, :actions, :patterns, :real_time,
                :periodic, :file, :logtype

    def initialize(head)
      @kind = head.kind
#uts "defining service #{head.name}" if @kind == 'service
      @kind = 'host' if @kind == 'app'

#        @services = {}
      @actions = MyList.new
      real_time = MyList.new
      periodic = MyList.new
      @real_time = {}
      @periodic = {}
      @file = {}
      @file['all'] = {'logtype' => LogFile.new}
      @converted = false
      @def_email = ''
      @opts = []
      @logtype = [] # added to by plugins
      @logtype_classes = {} # added to by plugins
      @ignore = nil
      @merge_files = $options['merge'] == 'yes'
      @priority = 0
      @feeds = [] # tell syslog-ng to add filter for this host to these output feeds
      @process_time_limit = nil

      super(head, false) # tell Section that we will handle subsections

      while (tok = nextT) && tok != '}'
        if tok == '[' then
          head = SectionHead.new

          head.name = 'default' unless head.name

          case head.kind
            when 'actions'
#	      ml = ActionList.new( head )
              @actions << ActionList.new(head).items
            when 'periodic'
              ml = MatchList.new(head, @opts, @file)
              @periodic[head.name] = MyList.new unless @periodic[head.name]
              @periodic[head.name] << ml.items
            when 'realtime'
              ml = MatchList.new(head, @opts, @file)
              @real_time[head.name] = MyList.new unless @real_time[head.name]
              @real_time[head.name] << ml.items
            else
              error("section #{head.kind} not valid here -- " +
                        "Have you missed a brace on previous section?")
              recover('}')
              next
          end
        else
          specificItem(tok)
        end
      end
      @actions = $global.actions unless @actions
#pp self
    end

    def get_options

      # options should contain a ssemicolon separated list of option=>value
      begin
        if look_ahead('/') or look_ahead('%r') then
          tok = 're'
        else
          tok = expect(/^(\w+)/, 'option name');
        end
        bad_tok = false

        case tok
          when 'email'
            if @kind == 'host' then
              expect('=>', nil, SAME_LINE)
              @def_email = expect(/^([^;\]]+)/, "email addresses")
              @def_email.strip!
            else
              bad_tok = true
            end
          when 'feeds'
            if @kind == 'host' then
              expect('=>', nil, SAME_LINE)
              begin
                @feeds.push(expect(/^(\w+)/, "name of output feed"))
              end until !look_ahead(',', ANYWHERE)
            else
              bad_tok = true
            end
          when 'priority'
            if @kind == 'host' then
              expect('=>', nil, SAME_LINE)
              @priority = expect(Integer, "search priority 0-9")
            else
              bad_tok = true
            end
          when 'ignore'
            @ignore = true
          when 're'
            if expect('re') then
              @pattern = @re
            else
              recover(/;|\]/)
            end
          when 'merge'
            @merge_files = (expect(%w( yes no)) == 'yes')
          when 'file'
            expect('=>')
            name = expect(/(\w+)/, 'file name')
            @file[name] = {} unless  @file[name]
            if look_ahead('(') then # have options for file
              expect('(')
              if (re = expect('re', '', ANYWHERE, OPTIONAL)) then
                @file[name]['logtype'] = @re
              else
                tok = expect(/(\w+)/, 'file option')
                if tok == 'ignore'
                  @file[name]['ignore'] = true
                elsif tok == 'email'
                  e = expect(/^([^);]+)/, "email addresses", ANYWHERE)
                  @file[name]['mail'] = e
                  @file[name]['mail'].strip
                  # must be a plugin name
                elsif @logtype_classes[tok]
                  @file[name]['logtype'] = @logtype_classes[tok]
                else
                  test = nil
                  tok = tok.capitalize
                  begin
                    eval "test = #{tok}.new(tok)" # known class ?
                  rescue SyntaxError, StandardError =>e
                    error("bad paramers or unknown action #{tok}: #{e}")
                    rest_of_line
                    @errors = true
                  end
                  if test then
                    @file[name] = {} unless @file[name]
                    @file[name]['logtype'] = test
                    @logtype_classes[tok] = test
                  end
                end
              end
              expect(')')
            else
              @file[name] = true
            end
          when 'limit'
            if expect('=>', nil, ANYWHERE, OPTIONAL)
              @process_time_limit = expect('Integer', "max seconds processing", SAME_LINE)
            end

          else
            if @kind == 'service' &&
                (t = @file['all']['logtype'].Tokens[tok])[1] == 'options' then
              if expect('=>', nil, ANYWHERE, OPTIONAL) then
                v = nil
                @opts << [tok, "'#{v}'"] if v = expect(t[0])
              else
                @opts << [tok, "'#{@name}'"]
              end
            else
              error("'#{tok}' is not a valid option for #{@kind}")
            end
        end
        if bad_tok then
          error("'#{tok}' is not a valid option for #{@kind}")
        end
      end while expect(';', nil, ANYWHERE, OPTIONAL)

      if !expect(']', "';' or ']' at end of section head") then
        error("Skipping to start of next section")
        recover(']')
      end
    end

# this handles the non section items in the section

    def merge_services(s)
      if service = $services[s] then
#          return if @services[s];  # all ready included                                                             
#          @services[s] = service
      else
        error("unknown service '#{s}' referenced in host/service #{@name} ")
        return
      end
        # merge in the file items

      service.file.each { |name, val|
        if val.class == Regexp
          @file[name]['re'] = val
        elsif !@file[name]
          @file[name] = val
        elsif (!@file[name]['logtype'] && val['logtype']&&
            val['logtype'].name != 'default')
          @file[name]['logtype'] = val['logtype']
        elsif (@file[name]['logtype'].name == 'default' &&
            val['logtype'].name != 'default')
          @file[name]['logtype'] = val['logtype']
        end
      }

      service.real_time.each { |key, value|
        if @real_time[key] then
          @real_time[key] << value
        else
          @real_time[key] = MyList.new(value)
        end
      }
      service.periodic.each { |key, value|
        if @periodic[key] then
          @periodic[key] << value
        else
          @periodic[key] = MyList.new(value)
        end
      }
        # merge in default actions
      if @kind == 'host' then
        @actions.merge_actions($global.actions, $run_type)
      end
    end


    def specificItem(first_token)

      case first_token
        when 'service'
          if tok = expect(/^(\w+)/, "service name") then
#pp tok, @file if @name == 'itsssolaris'
            merge_services(tok)
#pp "2", @file if @name == 'itsssolaris'
          else
            @errors = true
            rest_of_line # ignore the rest of the line
          end
        else
          @errors = true
          error("#{first_token} not valid in host section")
          rest_of_line # ignore the rest of the line
      end
    end

# defines which sections may be nested within this section
# Key is the section type the vailue is [ <name required>,
# class to parse section and where to store the result ]

    def sub_sections(kind)
      {'actions' => [nil, ActionList, @actions],
       'realtime' => ['optional', MatchList, real_time, @opts, @file],
       'periodic' => ['optional', MatchList, periodic, @opts, @file]
      }[kind]
    end

  end

# Parses a comma delimited list of strings...

  class CommaList < Section
    include Parser
    attr_reader :items

    def initialize(head)

      if !expect('{') then
        error("Skipping to start of next section")
        recover('[')
        @errors = true
        return nil
      end

#        reset_errors
      @items = getList

      error("Expecting '}' to end section") unless  token == '}'
#        @errors = reset_errors

    end
  end # CommaList
# ties events to actions.

  class ActionList < Section
    include Parser
    attr_reader :items

    @@all_events = {'alert' => 1, 'warn' => 1, 'report' => 1}

    def initialize(head)
      @items = []
      @action_classes = {}
      super(head)
    end

    def specificItem(first_token)
      events = []
      actions = []
      begin
        if first_token then
          tok = first_token
          first_token = nil
        else
          tok = expect(/(\w+)/, "Event Name", SAME_LINE)
        end
        if tok then
          tok.downcase!
        else
          @errors = true
        end

        if tok && @@all_events[token] then
          rt = expect(/^rt/i, nil, SAME_LINE, Optional)
          events.push(rt ? "rt-#{tok}" : tok)
        else
          error("'#{tok}' is not a valid event type")
          rest_of_line;
          @errors = true
          return nil
        end
      end while (tok = nextT(SAME_LINE)) == ','

      if tok != ':'
        error("Expecting a ':' separating events and action")
        rest_of_line(); # skip the rest of the line
        return nil
      end

      begin
        tok = expect(/^(\w+)/, "Action identifier").downcase
        tok = 'email' if tok == 'mail'
        case tok
          when 'acc'
            if i = timeInterval(Optional) then
              actions.push(['acc', i])
            else
              @errors = true
            end
          else # is it a Action plugin ?
            parms = expect(/\(([^)]+)\)/, nil, SAME_LINE, Optional) # there are parameters
            parms = '' unless parms
            if @action_classes[tok+parms]
              actions.push([tok, parms])
            else
              test = nil
              tok = tok.capitalize
              begin
                eval "test = Action::#{tok}.new(#{parms})" # known class ?
              rescue SyntaxError, StandardError =>e
                error("bad paramers or unknown action #{tok}: #{e}")
                rest_of_line
                @errors = true
              end

              if test then
                actions.push([tok, parms])
                @action_classes[tok+parms] = true
              end
            end
        end
      end while  nextT(SAME_LINE) == ',';

      if token
        error("Warning extraneous stuff ignored: " +
                  "'#{tok} #{line}'")
        rest_of_line
        @errors = true
      end
      events.each { |event|
        @items.push([event, actions])
      }
    end

    def sub_sections(kind)
      nil
    end
  end #  ActionList


  class MatchList < Section
    include Parser
    attr_reader :items
    attr_writer :items

    @@conditions = %w( re prog file test accumulate )
    @@actions = %w( alert warn count ignore drop proc incr switch )
    @@varNameRE = /^(\w+(?:\{[^}]+\})?)/

    def initialize(head, opts, file, init = false)
      @items = []
      @opts = opts
      @file = file
      super(head) unless init
    end

    def specificItem(first_token)

      # each Item is returned as an array of two elements
      # first is an array of conditions
      # second is an array of actions

      conditions = []
      actions = []
#pp " ",  @file

      tokens = @file['all']['logtype'].Tokens

      lf = nil


      if @name != 'default' # if the section is named then it may be the name of a LogFile class
        begin # in which case we want to know about the tokens
          eval "lf = #{@name.capitalize}.new"
          tokens = lf['logtype'].Tokens
        rescue SyntaxError, StandardError =>e
#            STDERR.puts "tokens = #{@name.capitalize}.new => #{e}"
        end

      end

      begin # while at end...
        if first_token then
          tok = first_token.dup
          if tok == '/' || tok == '%'
            back_up
            tok = 're'
          end
          first_token = nil
        else
          if look_ahead('/') or look_ahead('%r') then
            tok = 're'
          elsif ! (tok = expect(/^(\w+)/, 'condition name')) then
            rest_of_line
            return
          end
        end
        ok = false

        @opts.each { |value|
          conditions << [value[0], value[1], '==']
        }
        tok.downcase!
        case tok
          when 'file'
            tok = expect('String')
            tokens = @file[tok]['logtype'].Tokens if @file[tok] && @file[tok]['logtype']
            conditions.push(['fn', "'#{tok}'", '=='])
          when 're', 'rec'

            re = expect('re') # a
            re += 'i' unless tok == 'rec' # default is to ignore case

            if re.class != String then
              error("parser failed to extract re -- don't use delimters that mean things to REs")
              @errors = true
              rest_of_line
            else
              conditions.push(['re', re])
            end
          when 'incr'
            # incr  <report threshold> <time int> <string>
            if  (count = expect(/^(\d+)/, "interger Threshold", SAME_LINE)) && (
            (int = timeInterval) && label = quoted_string(SAME_LINE)) then
              conditions.push([tok, count, int, label])
            else
              err = true
            end
          when 'test'
            if expect(/^\$(\w+)/, nil, SAME_LINE, Optional)
              tt = 't_var'
              var = tok
            else
              tt= 't_val'
              var = expect(/^%(\d)/, "$var or %pat_no", SAME_LINE)
            end

            if op = expect(/^(==|=|<=|>=|!=|<|>)/, "<comp op>") then
              val = quoted_string(SAME_LINE, Optional) ? tok :
                  expect(/^(\d+)/, "<integer value>").to_i
              if val
                conditions.push([tt, var, op, val])
                ok = true
              end
            end
            if !defined? val then # syntax error
              rest_of_line
            end
            recover(/,|:/, SAME_LINE) unless ok
          else

            if t = tokens[tok] # it is a custom attribute
              value = nil
              op = expect(/^([!=<>~]{1,2})/, 'operator', SAME_LINE, Optional) || '=='
#              puts "tok #{tok} op #{op}" unless op == '=='
              if op_class = OPS[op] then
                if expect('(', '(', SAME_LINE, Optional) then # it is a range
                  (v1 = expect(t[0])) && expect('..') && (v2 = expect(t[0]))
                  if defined? v2 then
                    d = t[0].to_s == 'String' ? "'" : ""
                    value = "(#{d}#{v1}#{d}..#{d}#{v2}#{d})"
                    op = '==='
                    expect(')')
                  else
                    rest_of_line
                  end
                else
                  value = expect(op_class == 're' ? 're' : t[0])
                  value = "'#{value}'" if (t[0].to_s == 'String') && (op != '=~') && (op != '!~')
                end
                if op_class == 'string' && t[0] == 'Integer'
                  error("#{op} is valid only with Strings")
                  value = nil
                end

                conditions.push([tok, value, op]) if value
              else
                error("Unknown operator '#{op}'")
                rest_of_line
              end
            else
              error("'#{tok}' not valid here - expecting a condition")
              rest_of_line
            end
        end
      end while (tok = nextT(SAME_LINE)) && (tok == '&')

      if tok && tok != ':' then
        error("Expecting : or & or |")
        rest_of_line
        tok = nil
      end
      return nil unless tok

        # get the actions now
      begin
        errs = false
        tok = nextT(SAME_LINE).downcase
        case tok
          when 'alert', 'warn', 'switch'
            message = quoted_string(SAME_LINE, Optional)
            actions.push([tok, message])
          when 'ignore', 'drop'
            actions.push([tok])
            if x = rest_of_line then
              error("extraneous input '#{x}' after ignore or drop -- ignored")
              errs = true
            end
          when 'proc'
            params = nil
            if p = expect(/^(\w+)/) then
              params = expect(/\(([^)]+)\)/, 'parameters', SAME_LINE, Optional)
              if Procs.method_defined?( p.to_s )
                actions.push(['proc', p, params])
              else
                error("bad paramers or unknown proc #{p}(#{params}): #{e}")
                rest_of_line
                @errors = true
              end
            else
              errs = true
            end
          when 'count'
            # count <report threshold> <string>
            if (int = expect(/^(\d+)/, "interger Threshold", SAME_LINE)) &&
                (label = quoted_string(SAME_LINE)) then
              actions.push([tok, int, label])
            else
              err = true
            end
          when 'accumulate'
            if (var = expect(@@varNameRE, "$<variable name>", SAME_LINE)) &&
                (time = timeInterval(Optional)) then
              conditions.push([tok, var, time])
            else
              errs = true
            end
          else
            error("#{token} not valid here - expecting an action")
            rest_of_line
            @errors = true
        end
        if errs then # discard
          rest_of_line
          @errors = true
        end
      end while (tok = nextT(SAME_LINE)) && (tok == ',')

      @items.push([conditions, actions])

      if x = rest_of_line then
        error("extraneous input '#{x}' after ignore or drop -- ignored")
        @errors = true
      end

    end

    def sub_sections(kind)
      nil
    end

  end #Matchlist
end # Config


if $0 == 'Config.rb' then # someone is running us!
  Config::parse_config(ARGV.shift, 'realtime')

  print conf
end
