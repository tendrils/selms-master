#require "Codegen"
require "LogFile.rb"
class Host

  ALERT   = 0
  WARN    = 1
  UNUSUAL = 2
  SUMM    = 3


  attr_reader :src, :alerts, :warns, :name, :unusual, :conf, :count, :email,
              :ignore, :recs, :pattern, :file, :priority
             
  attr_writer :name

  class Accumulator
    def initialize( host, type, action, interval )
      @time = Time.now + interval
      @interval = interval
      @type = type
      @action = action
      @host = host
      @data = []
    end

    def <<(msg)
      @data << msg
    end 

    def check( time )

      if time > @time then
	if @data.size then
	  @action.async_send( @host, @type, @data )
	  @data = []   # empty the bucket  but keep it
	  1
	else
	  0 # tell caller to delete the bucket
	end
      else
	@data.size + 1
      end
    end
  end



  class Counter
    attr_reader :label
    def initialize ( label)
      @label = label
    end
  end

  class SimpleCounter < Counter
    attr_reader :val, :thresh
    def initialize (thresh, label)
      @val = 0
      @thresh = thresh
      super( label )
    end

    def incr
      @val += 1
    end

  end

  class TimeCounter < Counter
    def initialize( time, label )
      
      @items = time ? [] : 0
      @interval = time
      super( label )
    end
    
    def incr( time )
      if @interval then
        disc_t = time - @interval  # discard items with time less that this
        while @items.size > 0 && @items[0] < disc_t do
          @items.shift 
        end
        @items.push(time)
      else
        @items += 1
      end
    end

    def val
      @items.size  # number of items
    end

  end

  def initialize( conf, src )
  
    @file = conf.file
    @pattern = conf.pattern
    @name = conf.name.dup
    @ignore = conf.ignore
    @priority = conf.priority
    @count = {}
    @email = conf.def_email
#    @action_classes = {}
    $bucket = {}
    @recs = {}
    @recs['report'] = []
    @recs['alert'] = []
    @recs['warn'] = []
    @merge_files = conf.merge_files
  end

# substitute for % vars in strings

  def expand( s, mdata )
    return nil unless s
    begin
    string = s.dup
    string.gsub!(/%H/, @rec.h)
    string.gsub!(/%F/, @rec.fn);
    string.gsub!(/%1/, mdata[1] ? mdata[1] : '')
    string.gsub!(/%2/, mdata[2] ? mdata[2] : '')
    string.gsub!(/%3/, mdata[3] ? mdata[3] : '')
    string.gsub!(/%4/, mdata[4] ? mdata[4] : '')
    string.gsub!(/%5/, mdata[5] ? mdata[5] : '')
    return string
    rescue
      STDERR.puts "error substituting data into #{s}"
    end
  end

  def initialize_copy( from ) 

    @count = {}
    @count['alert'] = SimpleCounter.new(0, "Number of Alerts")
    @count['warn'] = SimpleCounter.new(0, "Number of Warnings")
    @count['ignore'] = SimpleCounter.new(0, "Number of Ignore records")
    @count['drop'] = SimpleCounter.new(0, "Number of dropped records")
    @pattern = from.pattern
    $bucket = {}
    @recs = {}
    @recs['report'] = []
    @recs['alert'] = []
    @recs['warn'] = []
  end 

  def log_files( log_dir, logf )
    
    if f = (  @file['all']  ) then
      c_logf = f.class != Regexp ? f : LogFile.new( @file['all'] ) 
    end
    
    if @merge_files then

      lf = c_logf.dup

      logf.each { | log |
        log =~ /^(.+)\.\d+/
        base_name = $1
        next if $options['file'] && $options['file'] != base_name
	next if base_name == 'cron' &&  @file['cron'] != 'process'
        next if @file[base_name] == 'ignore'               
	lf.open_lf( log_dir + '/' + log )
      }
      yield lf if lf.file
    else  # process files indivdually 
      logf.each { |log|
        log =~ /^(.+)\.\d+/
        base_name = $1
        next if $options['file'] && $options['file'] != base_name
	next if base_name == 'cron' &&  @file['cron'] != 'process'
        next if @file[base_name] == 'ignore'	
	count = 0
	if f = (  @file[base_name] || @file['all'] ) then
          f.to_s =~ /#<(\w+):/
          rs = $1.downcase
          @rule_set = @file[base_name].to_s.downcase if @file[base_name]  ###########  temp fudge -- fix this
	  c_logf = f.class != Regexp ? f : LogFile.new( f ) 
          @rule_set = '_'+rs
          begin
            self.send @rule_set, nil, nil 
          rescue StandardError => ex
            @rule_set = '_default'
          end
        end


	lf = c_logf.dup
        lf.open_lf( log_dir + '/' + log )

	pp "using logformat:", c_logf.to_s if $options['debug.split']
	yield lf
      }
  end
end

# does a periodic scan of all files associated with self 

  def pscan( log_dir, hostname )

    puts "in Host::pscan #{hostname}" if $options['debug.hosts'] 

   @logf = []

    logs = Dir.new( log_dir );
    logs.each { |filename|
      next unless filename =~ /(.+)\.\d{8}$/
      @logf.push( filename )
   }

   begin
     log_files(log_dir, @logf) { |lf|
       
       while @rec = lf.gets

	  pp 'preliminary split:', @rec if $options['debug.split']
	 next unless @rec.split
	 pp '', "final split", @rec if $options['debug.split']
	 break unless self.send @rule_set, 'TEST', @rec 
	 if $options['max_log_recs'] && 
	     recs['report'].size + recs['alert'].size + recs['warn'].size  >= $options['max_log_recs'] then
	   lf.abort
	   alert(  "more than #{$options['max_log_recs'].to_s} reported records ")
	   break;
	 end 
       end
       _post_default()   # run any post code
     }
#   rescue IOError
#     STDERR.puts "IO error accurred while #{$fstate} log file file " +
#       "for #{hostname}: #{$!}"
#     post()
   end
 end
 end
