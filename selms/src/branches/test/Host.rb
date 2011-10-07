#require "Codegen"
require "LogFile.rb"
require "Procs.rb"
class Host

  include Procs

  ALERT   = 0
  WARN    = 1
  UNUSUAL = 2
  SUMM    = 3
  POST    = 4


  attr_reader :src, :alerts, :warns, :name, :unusual, :conf, :count, :email,
              :ignore, :recs, :pattern, :file, :priority, :rule_set
             
  attr_writer :name, :rule_set, :recs

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

    def incr ( inc=1 )
      @val += inc
    end

  end

  class TimeCounter < Counter
    def initialize( count, time, label )
      
      @items = time ? [] : 0
      @interval = time
      @threshold = count
      super( label )
    end
    
    def incr( time, inc=1 )
      if @interval then
        disc_t = time - @interval  # discard items with time less that this

        while @items.size > 0 && @items[0] < disc_t do
          @items.shift 
        end
        @items.push(time)
      else
        @items += inc
      end
      if @items.size >= @threshold then
	@items=[]
	return TRUE
      end
    end

    def check
      @items.size >= @threshold
    end

    def val
      @items.size  # number of items
    end

  end

  def incr_check( m_data, threshold, interval, label, time, count)
    label = expand(label, m_data) if label =~/%/ && ( defined? m_data )
    @count[label] = TimeCounter.new(threshold, interval , label ) unless @count[label]
#    puts "incr count #{label} #{@count[label].val}"
    return @count[label].incr(time, count) ? "#{label}: #{threshold} events in #{interval} seconds" : nil
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
    @recs['post'] = []
    @merge_files = conf.merge_files
    @rule_set = '_' + $options['sub-type']
  end

# substitute for % vars in strings

  def expand( s, mdata )
    return nil unless s
    begin
    m = ''
    string = s.dup
    1.upto(mdata.size-1) { |i| # substitute %n for nth matched string, handle embedded '\'s
      if  mdata[i] then
        m = mdata[i].dup ? mdata[i].dup : ''
	string.gsub!("%#{i}", m.gsub('\\', '\\\\\\\\') ) 
      end
    }
    string.gsub!(/%H/, @rec.h)
    string.gsub!(/%F/, @rec.fn);
    return string
    rescue
      STDERR.puts "error substituting data '#{m}' into '#{s}':#{$!}"
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
    @recs['post'] = []
    @scanner = '_default'
  end

  def log_files(log_dir, logf=nil)


    if !logf
      lf = @file[$options['log_type']]['logtype']
      lf.open_lf(log_dir)

      yield lf if lf.file
    elsif @merge_files then

      logf.each { |log|
        log =~ /^(.+)\.\d+/
        base_name = $1
        next if $options['file'] != base_name
        next if base_name == 'cron' && @file['cron'] != 'process'
        next if @file[base_name]['ignore']

        l = @file[base_name] ? base_name : 'all'

        lf.open_lf(log_dir + '/' + log)
      }
      yield lf if lf.file
    else # process files indivdually
      logf.each { |log|
        log =~ /^(.+)\.\d+/
        base_name = $1

        l = @file[base_name] ? base_name : 'all'
        next if  $options['file'] && $options['file'] != base_name
        next if base_name == 'cron' && @file['cron'] != 'process'
        next if @file[base_name] && @file[base_name]['ignore']

        lf = @file[l]['re'] ? LogFile.new(@file[l]['re'], log_dir + '/' + log) : @file[l]['logtype']
        count = 0
        if f = (@file[base_name] || @file['all']) then
          f.to_s =~ /#<(\w+):/
          rs = $1.downcase
          @rule_set = @file[base_name].to_s.downcase if @file[base_name] ###########  temp fudge -- fix this
          c_logf = f.class != Regexp ? f : LogFile.new(f, log_dir + '/' + log)
          @rule_set = '_'+rs
          begin
puts "rule_set #{@rule_set}"
            self.send @rule_set, nil, nil
          rescue StandardError => ex
            @rule_set = '_default'
          end
        end

        lf.open_lf(log_dir + '/' + log)

        pp "using logformat:", c_logf.to_s if $options['debug.split']
        yield lf
      }
    end
  end

# does a periodic scan of all files associated with self 

  def pscan(log_dir, hostname)

    puts "in Host::pscan #{hostname}" if $options['debug.hosts']

    @logf = []

    if File.directory?(log_dir)
      logs = Dir.new(log_dir);
      logs.each { |filename|
        next unless filename =~ /(.+)\.\d{8}$/
        @logf.push(filename)
      }
    elsif File.exists?(log_dir)
      @logf = nil #   Mark as a single file
    else
      return nil
    end

    begin
      log_files(log_dir, @logf) { |lf|

        while @rec = lf.gets
          pp '', "final split", @rec if $options['debug.split']
          break unless self.send @rule_set, 'TEST', @rec
          if $options['max_log_recs'] &&
              recs['report'].size + recs['alert'].size + recs['warn'].size >= $options['max_log_recs'] then
            lf.abort
            alert("more than #{$options['max_log_recs'].to_s} reported records ")
            break;
          end
        end
        self.send '_post'+@rule_set # run any post code
      }
#   rescue IOError
#     STDERR.puts "IO error accurred while #{$fstate} log file file " +
#       "for #{hostname}: #{$!}"
#     post()
    end
  end
end
