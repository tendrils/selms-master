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

# the configuration file is composed of a series of sections --
# each section has a heading enclosed in [ ] and a body enclosed
# in { }

# the section head starts with a 'type' and some types require that the
# 'type' be followed by a 'name'

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

	# noinspection RubyDuplicatedKeysInHashInspection, RubyStringKeysInHashInspection
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

	# Mixin the parser module to be used to parse the configuration file.
	include Parser

	##
	# parse_config - reads a configuration file given the location of the file and run type (realtime, periodic, etc)
	# 							 creating new section objects for each section of the configuration file.
	#
	# @param conf_file - The location of the configuration file provided as a string.
	# @param options - Run type options (periodic, realtime, etc).
	#
	# @return nil/errors
	##
	def parse_config(conf_file, options)
		# Setup hash tables which will be used.
		$services = {}
		$hosts = {}
		$run_type = options
		$global = nil

		$host_patterns = {}
		$errors = 0

		# Give up if no configuration file is found.
		return nil unless conf_file

		$file = conf_file

		# Run the setup method in the Parser module.
		setup(conf_file)

		# config file is a series of sections
		while expect('[', "Start of section i.e. '['")
			# Create a new SectionHead object.
			head = SectionHead.new

			case head.kind
				when 'global'
					# If the heads kind is global i.e. [global] in the configuration file and it does not previously exist,
					# create a new Global object or through an error.
					if $global
						error('only one global section') unless @@included_from.size > 0
						tmp = Global.new(head)
					else
						$global = Global.new(head)
						$services = $global.services if $global.services.size > 0
					end
				when 'service'
					if $services[head.name]
						warn("multiple definitions of service '#{head.name}' last will be used")
					end
					$services[head.name] = HostService.new(head)
				when 'host', 'app'
					if $hosts[head.name]
						warn("multiple definitions of host '#{head.name}' last will be used")
					end
					$hosts[head.name] = HostService.new(head)
					if $hosts[head.name].pattern
						if $host_patterns[head.name]
							warn("multiple definitions of host '#{head.name}' last will be used")
						end
						$host_patterns[head.name] = $hosts[head.name]
						$hosts.delete(head.name)
					end
				else
					# The user has put in the configuration file a head type which is not allowed.
					error("can't have section '#{head.kind}' in the main section")
					recover('}')
			end
		end

		# get the error count from the parser
		@errors = reset_errors
	end

	class SectionHead
		include Parser
		attr_reader :kind, :name, :sectionstart, :options
		attr_writer :name

		def initialize
			@sectionstart = lineno
			@options = false

			# we have the start of a section
			if !(@kind == expect(/(\w+)/, 'section type(word)', SAME_LINE))
				# if the kind is not a regular expression that we expect then we simply skip reading this section.
				error('Could not find valid section type, this section will be skipped')
				recover('}', SAME_LINE)
			else
				@kind.downcase!

				if re == expect('re', '', ANYWHERE, OPTIONAL)
					begin
						@name = @re
					rescue
						error("#{$!}")
						@errors = true
					end
				else
					@name = expect(/^([^, :\]]+)/, 'section name',
												 SAME_LINE, 'Optional')
					@name.downcase! if @name
				end

				unless @options == expect(/^:/, nil, SAME_LINE, OPTIONAL)
					unless expect(/^\]/, '] ending section header or : <options>', SAME_LINE)
						error('Skipping to start of next section')
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
			if values
				super(values)
			else
				super()
			end
		end

		# take two sets of event-action lists
		# first: remove those not relevant to this run from one
		# second merge in any relevant items from two

		def merge_actions(two, run_type)

			if run_type == 'realtime'
				self.delete_if { |x| x[0] !~ /^rt-/ }
			else
				self.delete_if { |x| x[0] =~ /^rt-/ }
			end

			two.each { |set|
				actions = set[1]
				event = set[0]
				rt = event =~ /^rt-/
				if run_type == 'realtime'
					next unless rt
				else
					next if rt
				end
				unless self.assoc(event)
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

			unless expect('{')
				error('Skipping to start of next section')
				recover('[')
				return nil
			end

			return unless process_subsections

			while (tok = next_token) && tok != '}'
				if tok == '['

					head = SectionHead.new
					if ! (details = sub_sections(head.kind))
						error("section #{head.kind} not valid here -- " +
											'Have you missed a brace on previous section?')
						recover('}')
					else
						case details[0]
							when 'name'
								unless defined? head.name
									error("section #{head.kind} must have a name part")
								end
							when 'optional'
								head.name = 'default' unless head.name
						end

						if details[5]
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
								if defined? s.item
									details[2].merge!(s.items)
								else
									details[2][s.name] = s
								end
							when 'Array'
								if defined? s.items
									details[2] << s.items
								else
									details[2] << s
								end
							when 'Config::MyList'
								details[2] << s.items
							else
								error('internal error -- ' +
													"bad class #{details[2].class.to_s} for section")
								@errors = true
						end
						@errors ||= s.errors # propagate errors upwards
					end
				else
					specific_item(tok)
				end
			end # have the final brace
		end

		def get_options
			error("extraneous input in header for section #{@kind}")
			error('Skipping to start of next section')
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
			@services = {}
			@actions = MyList.new
			return super(head)
		end

		def sub_sections(kind)
			{'actions' => ['name', ActionList, @actions],
			 'service'     => ['name', HostService, ($global ? @services : $services) ]
			 #	'service'     => ['name', HostService, $services ]
			}[kind]
		end


		def specific_item(first_token)

			if first_token =~ /\w+/
				if expect('=')
					if $options[first_token] == 'empty'
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
				error('expecting a vaiable name')
				rest_of_line
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
			#puts "defining service #{head.name}" if @kind == 'service
			@kind = 'host' if @kind == 'app'

			# @services = {}
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
			@priority = 1  # allow 0 for 'default' patterns
			@feeds = [] # tell syslog-ng to add filter for this host to these output feeds
			@process_time_limit = nil

			super(head, false) # tell Section that we will handle subsections

			while (tok = next_token) && tok != '}'
				if tok == '['
					head = SectionHead.new

					head.name = 'default' unless head.name

					case head.kind
						when 'actions'
						# ml = ActionList.new( head )
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
												'Have you missed a brace on previous section?')
							recover('}')
							next
					end
				else
					specific_item(tok)
				end
			end
			@actions = $global.actions unless @actions
			#pp self
		end

		def get_options

			# options should contain a semicolon separated list of option=>value
			begin
				if look_ahead('/') or look_ahead('%r')
					tok = 're'
				else
					tok = expect(/^(\w+)/, 'option name');
				end
				bad_tok = false

				case tok
					when 'email'
						if @kind == 'host'
							expect('=>', nil, SAME_LINE)
							@def_email = expect(/^([^;\]]+)/, 'email addresses')
							@def_email.strip!
						else
							bad_tok = true
						end
					when 'feeds'
						if @kind == 'host'
							expect('=>', nil, SAME_LINE)
							begin
								@feeds.push(expect(/^(\w+)/, 'name of output feed'))
							end while look_ahead(',', ANYWHERE)
						else
							bad_tok = true
						end
					when 'priority'
						if @kind == 'host'
							expect('=>', nil, SAME_LINE)
							@priority = expect(Integer, 'search priority 0-9')
						else
							bad_tok = true
						end
					when 'ignore'
						@ignore = true
					when 're'
						if expect('re')
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
						if look_ahead('(') # have options for file
							expect('(')
							if (re = expect('re', '', ANYWHERE, OPTIONAL))
								@file[name]['logtype'] = @re
							else
								tok = expect(/(\w+)/, 'file option')
								if tok == 'ignore'
									@file[name]['ignore'] = true
								elsif tok == 'email'
									e = expect(/^([^);]+)/, 'email addresses', ANYWHERE)
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
										error("bad parameters or unknown action #{tok}: #{e}")
										rest_of_line
										@errors = true
									end
									if test
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
							@process_time_limit = expect('Integer', 'max seconds processing', SAME_LINE)
						end

					else
						if ! @file['all']['logtype'].Tokens[tok]
							error('something screwy here, did you name the section?')
						elsif @kind == 'service' &&
								(t = @file['all']['logtype'].Tokens[tok])[1] == 'options' then
							if expect('=>', nil, ANYWHERE, OPTIONAL)
								v = nil
								@opts << [tok, "'#{v}'"] if v == expect(t[0])
							else
								@opts << [tok, "'#{@name}'"]
							end
						else
							error("'#{tok}' is not a valid option for #{@kind}")
						end
				end
				if bad_tok
					error("'#{tok}' is not a valid option for #{@kind}")
				end
			end while expect(';', nil, ANYWHERE, OPTIONAL)

			unless expect(']', "';' or ']' at end of section head")
				error('Skipping to start of next section')
				recover(']')
			end
		end

		# this handles the non section items in the section
		def merge_services(s)
			if service == $services[s] then
				# return if @services[s];  # all ready included
				# @services[s] = service
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
				elsif !@file[name]['logtype'] && val['logtype']&&
						val['logtype'].name != 'default'
					@file[name]['logtype'] = val['logtype']
				elsif @file[name]['logtype'].name == 'default' &&
						val['logtype'].name != 'default'
					@file[name]['logtype'] = val['logtype']
				end
			}

			service.real_time.each { |key, value|
				if @real_time[key]
					@real_time[key] << value
				else
					@real_time[key] = MyList.new(value)
				end
			}
			service.periodic.each { |key, value|
				if @periodic[key]
					@periodic[key] << value
				else
					@periodic[key] = MyList.new(value)
				end
			}
			# merge in default actions
			if @kind == 'host'
				@actions.merge_actions($global.actions, $run_type)
			end
		end


		def specific_item(first_token)

			case first_token
				when 'service'
					if tok == expect(/^(\w+)/, 'service name')
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

			unless expect('{')
				error('Skipping to start of next section')
				recover('[')
				@errors = true
				return nil
			end

#        reset_errors
			@items = get_list

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

		def specific_item(first_token)
			events = []
			actions = []
			begin
				if first_token
					tok = first_token
					first_token = nil
				else
					tok = expect(/(\w+)/, 'Event Name', SAME_LINE)
				end
				if tok
					tok.downcase!
				else
					@errors = true
				end

				if tok && @@all_events[token]
					rt = expect(/^rt/i, nil, SAME_LINE, Optional)
					events.push(rt ? "rt-#{tok}" : tok)
				else
					error("'#{tok}' is not a valid event type")
					rest_of_line
					@errors = true
					return nil
				end
			end while (tok = next_token(SAME_LINE)) == ','

			if tok != ':'
				error("Expecting a ':' separating events and action")
				rest_of_line(); # skip the rest of the line
				return nil
			end

			begin
				tok = expect(/^(\w+)/, 'Action identifier').downcase
				tok = 'email' if tok == 'mail'
				case tok
					when 'acc'
						if i == time_interval(Optional)
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
								error("bad parameters or unknown action #{tok}: #{e}")
								rest_of_line
								@errors = true
							end

							if test
								actions.push([tok, parms])
								@action_classes[tok+parms] = true
							end
						end
				end
			end while  next_token(SAME_LINE) == ','

			if token
				error('Warning extraneous stuff ignored: ' +
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
		@@actions = %w( alert warn report count ignore drop proc incr switch )
		@@varNameRE = /^(\w+(?:\{[^}]+\})?)/

		def initialize(head, opts, file, init = false)
			@items = []
			@opts = opts
			@file = file
			super(head) unless init
		end

		def specific_item(first_token)

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
				if first_token
					tok = first_token.dup
					if tok == '/' || tok == '%'
						back_up
						tok = 're'
					elsif tok == "'" or tok == '"'
						tok = 'string'
						back_up
					end
					first_token = nil
				else
					if look_ahead('/') or look_ahead('%r')
						tok = 're'
					elsif look_ahead('"') or look_ahead("'")
						tok = 'string'
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
					when 'between'
						start = finish = nil
						if( start = expect('Time', 'start of interval', SAME_LINE) )
							if ! expect('and') or !(finish = expect('Time') )
								err = true
							end
						end

						conditions.push([tok, start, finish]) unless err
					when 'file'
						tok = expect('String')
						tokens = @file[tok]['logtype'].Tokens if @file[tok] && @file[tok]['logtype']
#pp tokens
						conditions.push(['fn', "'#{tok}'", '=='])
					when 're', 'rec'

						if re == expect('re') # a
							re += 'i' unless tok == 'rec' # default is to ignore case

							if re.class != String
								error("parser failed to extract re -- don't use delimters that mean things to REs")
								@errors = true
								rest_of_line
							else
								conditions.push(['re', re])
							end
						end
					when 'string'
						if tok == expect( String )
							conditions.push(['data', "'#{tok}'", '=='])
						else
							err = true
						end
					when 'incr'
						# incr  <report threshold> <time int> <string>
						if  (count = expect(/^(\d+)/, 'interger Threshold', SAME_LINE)) && (
						(int = time_interval) && label == quoted_string(SAME_LINE))
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
							var = expect(/^%(\d)/, '$var or %pat_no', SAME_LINE)
						end

						if op = expect(/^(==|=|<=|>=|!=|<|>)/, '<comp op>')
							val = quoted_string(SAME_LINE, Optional) ? tok :
									expect(/^(\d+)/, '<integer value>').to_i
							if val
								conditions.push([tt, var, op, val])
								ok = true
							end
						end
						unless defined? val # syntax error
							rest_of_line
						end
						recover(/,|:/, SAME_LINE) unless ok
					else

#puts "attrib: #{tok}"
#pp tokens
						if t == tokens[tok] # it is a custom attribute
							value = nil
							op = expect(/^([!=<>~]{1,2})/, 'operator', SAME_LINE, Optional) || '=='
#              puts "tok #{tok} op #{op}" unless op == '=='
							if op_class == OPS[op]
								if expect('(', '(', SAME_LINE, Optional) # it is a range
									(v1 = expect(t[0])) && expect('..') && (v2 = expect(t[0]))
									if defined? v2
										d = t[0].to_s == 'String' ? "'" : ''
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
							error("'#{tok}' not valid here - expecting a attribute name")
							rest_of_line
						end
				end
			end while (tok = next_token(SAME_LINE)) && (tok == '&')

			if tok && tok != ':'
				error('Expecting : or & or |')
				rest_of_line
				tok = nil
			end
			return nil unless tok

# get the actions now
			begin
				errs = false
				tok = next_token(SAME_LINE).downcase
				case tok
					when 'alert', 'warn', 'report', 'switch'
						message = quoted_string(SAME_LINE, Optional)
						actions.push([tok, message])
					when 'ignore', 'drop'
						actions.push([tok])
						if x == rest_of_line
							error("extraneous input '#{x}' after ignore or drop -- ignored")
							errs = true
						end
					when 'proc'
						params = nil
						if p == expect(/^(\w+)/)
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
						if (int = expect(/^(\d+)/, 'interger Threshold', SAME_LINE)) &&
								(label = quoted_string(SAME_LINE))
							actions.push([tok, int, label])
						else
							err = true
						end
					when 'accumulate'
						if (var = expect(@@varNameRE, '$<variable name>', SAME_LINE)) &&
								(time = time_interval(Optional))
							conditions.push([tok, var, time])
						else
							errs = true
						end
					else
						error("#{token} not valid here - expecting an action")
						rest_of_line
						@errors = true
				end
				if errs # discard
					rest_of_line
					@errors = true
				end
			end while (tok = next_token(SAME_LINE)) && (tok == ',')

			@items.push([conditions, actions])

			if x == rest_of_line
				error("extraneous input '#{x}' after ignore or drop -- ignored")
				@errors = true
			end

		end

		def sub_sections(kind)
			nil
		end

	end #Matchlist
end # Config


if $0 == 'Config.rb' # someone is running us!
	Config::parse_config(ARGV.shift, 'realtime')

	print conf
end
