# change this if you fiddle with the syslog-ng templates!!!   Should be a global config option??

LOG_BITS = /^([^:]+):\s+(.+)?/
# token change
class LogFile

=begin rdoc
The LogFile class implements a straight forward interface for SELMS to read and parse 
log files. It is assumed that logfiles with differing formats will be handled by classes 
which inherit this one.

The class interacts with the configuration parser by defining what objects one can test 
in the matching section of the config - by default these are data and proc

The process of parsing the log record has two phases:
  1/ the record si split up according to the RE set in Class LogStore  -- this is normally the same for all files on a host as the format is set by the local syslog daemon.
  2/ the message portion is then split up into components that can then be tested by the matching process --
     by default we use LOG_BITS 

=end
  attr_reader :Tokens, :name, :rec, :file

  def initialize(name=nil, fn=nil, split_p=nil, head=nil)

    @Tokens = {
        'proc' => [String, 'options'],
        'int' => [Integer, 'options'] # so we can test ints in default setup
    }
    @name = name || 'default'
    @head = head ? Regexp.new(head) : $log_store.log_head
    @split_p = split_p ? Regexp.new(split_p) : LOG_BITS
    @rec = nil
    @l_rec = nil
    @file = nil
    @off_name = nil
    @no_look_ahead = nil
    @recs = @split_failures = 0
    @rc = Record
    if $options['sub-type'] != 'default'
      begin
        @ST = capitalise(self.class.to_s+"::#{$options['sub-type']}")
        @ST.process( nil )
      rescue
        @ST = nil
      end
    end
  end



=begin rdoc 
gets reads a single logical record 

gets collapses multiple identical records and appends a -- repeated n times to the record
  much of the complexity of gets is due to the necessary read ahead to handle this functionality
gets also will merge records from a number of log files for the same host into time order so that
  records come out interleaved in periodic reports the read ahead is also necessary to support merging
=end
  def gets(l = nil, raw = nil) # set l for initial read
=begin rdoc
  _l_ is the index of the file to read (0 unless merging is taking place)  It indicates that this is 
  the initial call for a file to do a read ahead for subsquent comparsions.  (But see no_look_ahead)

  _raw_ is used to pass a physical record into gets -- normally only used for realtime processing --- why ??

 _no_look_ahead_  tells gets not to read ahead and collaspe mutiple identical records
    used by classes that read multiple physical records for each logical record
=end

    puts "Gets:" if  $options['debug.gets']

    if $run_type == 'realtime'
      r = @rc.new(raw, @head, @split_p)
      return r
    end

    return nil if !@file || @file.size == 0

    @recs += 1
    return nil if $options['max_read_recs'] && @recs > $options['max_read_recs']
    initial = l
    previous_rec = nil
    count = 0 # number of duplicates
    r = nil # what we return -- define out side loop
    time = 0 # time of first dupicate

    puts "Gets: initial #{l}" if initial && $options['debug.gets']

    catch :new_file do
      begin # loop while records are the same
        save = l
# merge multiple input files - If _l_ is given the read that file
        if !initial then # select next file with earliest log record
          l = 0
          for i in 1 .. @file.size - 1
            l = i if @rec[l].utime > @rec[i].utime
          end
        end
        throw :new_file if save && save != l && count > 0
        puts "gets: index :#{l} count = #{count}" if $options['debug.gets']
# _l_ now contains the index of the next file to read from
        r = initial ? @rc.new : @rec[l].dup unless @no_look_ahead

        closed = false
        begin # loop to collaspe repeated records
          if raw = @file[l].gets then
            count += 1
            puts "gets: raw #{count} #{raw}" if $options['debug.gets']
            if initial
              previous_rec = @rc.new # null entry
            else
              puts "gets: not initial #{count}" if $options['debug.gets']
              previous_rec = @rec[l].dup if count == 1 && !@no_look_ahead
            end
            begin # corrupt offset or eof ??
              @rec[l] = @rc.new(raw, @head, @split_p)
            rescue NoMethodError
              warn "NoMethodError file #{@fn[l]} type #{@name} #{$!} "
              next
            end


            @rec[l].fn = @fn[l]
            time = @rec[l].time if count == 1 # first time
          else # end of file
            puts "gets: end of file #{l} count  #{count}" if $options['debug.gets']
            if !initial || @closing[l] || count != 1 # don't loose last record!
              close_lf(l)
                                                     #              puts "closing file #{l}"
            else
              @closing[l] = true
            end
            closed = true
          end # gets

          if initial && !(defined? @rec[l].data) then # corrupt offset value?
            count = 0
            puts "gets: corrupt record" if $options['debug.gets']
            next
          end

          if @no_look_ahead # we have the record just return
            puts "gets: no_look_ahead return '#{@rec[l].data}'" if (defined? @rec[l].data) && $options['debug.gets']
            return @rec[l]
          end

          repeat = (@rec[l].data =~ /^last message repeated (\d+) times/ ||
              @rec[l].data =~ /^Previous message occurred (\d+) times./)
          if !closed && repeat
            if initial
              @rec[l] = nil
              count = 0
            else
              puts "repeated #{$1}" if $options['debug.gets']
              count += $1.to_i
              @rec[l] = previous_rec
            end
          end
        end until (closed || (@rec[l] && @rec[l].data))

        if $options['debug.gets'] && !repeat
          puts "comparing"
          puts @rec[l].data unless closed
          puts previous_rec.data unless closed
        end
      end while (!closed && !repeat && @rec[l].data == previous_rec.data)
    end

    begin
      r.method(:data) # corrupt offset or eof ??
    rescue NameError
      return false
    end

    puts "final count #{count}" if $options['debug.gets']
    r.count = count
    if count > 1
      if !r.orec # something broken in the parsing
        STDERR.puts "Parsing problems in file #{@fn} for host #{@rec[0].h} parser #{@rc}- aborting this file"
        return nil
      end

      r.orec << " -- repeated #{count} times since #{time}"
    end

    puts "return '#{r.data}'" if !initial && $options['debug.gets']

    return r unless initial

  end

  def open_lf(fn)

    if $run_type != 'realtime'
      off_name = fn + '-' + $options['offset']
      all, n = fn.match(/.+\/(\w+)\.\d+/).to_a
      offset = nil
    end
    if !@file then
      @file = []
      @rec = []
      @cache = []
      @off_name = []
      @closing = []
      @fn = []
    end

    $fstate = 'opening'
    if $run_type != 'realtime' && (File.file? off_name) && !$options['no_offset'] && !$options['one_file']
      File::open(off_name) { |o|
        offset = o.gets.to_i
      }
    end

    f = File.open(fn)
    if f then
      puts "opened file #{fn} log type #{self}" if $options['debug.split'] || $options['debug.gets'] ||$options['debug.files']
    else
      puts(STDERR, "failed to open #{fn} #{$!}")
      return nil
    end
    $fstate = 'seeking'
    f.seek(offset) if offset
    $fstate = 'reading'

    closed = false
    l = @file.size
    r = nil
    @file[l] = f
    @closing[l] = false
    @fn[l] = n
    @off_name[l] = off_name

    gets(l) unless @no_look_ahead # to prime the look ahead buffer for finding duplicate records
  end

  def abort
    while @file
      @file[0].seek(0, IO::SEEK_END);
      close_lf(0)
    end
  end

# have to drop the look a head!!
  def close_lf(lf = nil)

    offset = @file[lf].tell
    @file[lf].close
    off_n = @off_name[lf]

    if @file.size == 1 then # last one
      @file = nil
    else
      @file.slice!(lf)
      @rec.slice!(lf)
      @off_name.slice!(lf)
    end

    unless ($options['no_write_offset'] || $options['no_offset']) then
      File::open(off_n, 'w') { |o|
        o.puts offset.to_s
      }
    end
  end

# default log splitter                                                                                                 
  class Record
    attr_reader :count, :time, :utime, :h, :record, :proc, :orec, :data, :int, :fn, :extra_data, :raw
    attr_writer :fn, :count

    def initialize(raw=nil, pat=nil, split_p=nil)

      @raw = raw
      @split_p = split_p
      @pat = pat
      @time = nil
      @utime = nil
      @h = nil
      @proc = nil
      @orec = nil
      @fn = ''
      @data = ''
      @extra_data = ''
      @count = 0
      return unless raw
      all, @utime, @time, @h, @data = raw.match(pat).to_a
#puts "#{@h}-#{@data}"
      @utime = @utime.to_i
      split
    end

# default log splitter

    def split
      return nil unless @data
      all, p, data = @data.match(@split_p).to_a

      if !all # split failed
        @orec = nil
      else
        @data = data if data
        if data && (@data.sub!(/^(pam_\w+\[\d+\]):/, p) || @data.sub!(/^\((pam_\w+)\)/, p))
          p=$1
        end

        @proc = canonical_proc(p)
        @orec = "#{@time} #{@h}: #{p}: '#{@data}'"
      end
    end

    def canonical_proc(p)
      p = '' unless p
      if p =~ /last message repeated/ then
        proc = p
      elsif p =~ /^([-a-zA-Z0-9 ]+)(?:\[(\d+)\])?$/ then # proc namd[1234]
        proc = $1
        pid = $2
      elsif p =~ /^([-a-zA-Z0-9.]+)(?:\[(\d+)\])?$/ then
        proc = $1
        pid = $2
      elsif p =~ /^(\w+)(?:[- 0-9.]+)?(?:\[(\d+)\])?$/ then # syslogd 1.4.1
        proc = $1
        pid = $2
      elsif p =~ %r|/([^/]+)\[(\d+)\]$| then #  postfix/smtpd[642]
        proc = $1
        pid = $2
      elsif p =~ %r|/([^/]+)$| then # /usr/bin/sudo
        proc = $1
        pid = ''
      elsif p =~ %r!^(\w+)\(\S+\)\[(\d+)\]$! then # ssh(pam_unix)[899]
        proc = $1
        pid = $2
      else
        proc = ''
      end
      proc.downcase
    end
  end


end

