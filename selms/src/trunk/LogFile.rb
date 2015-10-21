
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

NOTE!!!  At this time selms does not handle multi line records
  it will throw away any record that fails the initial parse
=end
    attr_reader  :Tokens, :name, :rec, :file 

    def initialize( name=nil, fn=nil, split_p=nil, head=nil, continuation=nil)

      @Tokens = {
	'proc' => [ String, 'options' ],
	'int' => [ Integer, 'options' ]  # so we can test ints in default setup
      }
      @name = name || 'default'
      @head = head ?  Regexp.new(head) : $log_store.log_head
      @split_p = split_p ? Regexp.new(split_p) : LOG_BITS
      @rec = nil
      @l_rec = nil
      @file = nil
      @off_name = nil
      @no_look_ahead = nil
      @recs = @split_failures = 0
      @rc = Record
      @line = 0
      @continuation = Regexp.new(continuation) if continuation; 
    end

=begin rdoc 
gets reads a single logical record 
gets collapses multiple identical records and appends a -- repeated n times to the record
  much of the complexity of gets is due to the necessary read ahead to handle this functionality
gets also will merge records from a number of log files for the same host into time order so that
  records come out interleaved in periodic reports the read ahead is also necessary to support merging
=end
    def gets( file_index = nil, raw = nil )  # set l for initial read
=begin rdoc
  _l_ is the index of the file to read (0 unless merging is taking place)  It indicates that this is 
  the initial call for a file to do a read ahead for subsquent comparsions.  (But see no_look_ahead)

  _raw_ is used to pass a physical record into gets -- normally only used for realtime processing --- why ??

 _no_look_ahead_  tells gets not to read ahead and collaspe mutiple identical records
    used by classes that read multiple physical records for each logical record
=end

#      puts "Gets: #{l} #{raw} #{continuation}" if  $options['debug.gets'] 

      if $run_type == 'realtime'
        r =  @rc.new( raw, @head, @split_p)
        return r
      end

      return nil if ! @file || @file.size == 0

      @recs += 1
      initial = file_index
      previous_rec = nil
      count = 0  # number of duplicates  
      r = nil   # what we return -- define out side loop
      time = 0  # time of first dupicate
      cont = nil  # last rec was a continuation

      puts "Gets: initial '#{initial}', index #{file_index}" if $options['debug.gets'] 
      
      catch :new_file do
        begin  # loop while records are the same
          save_index = file_index
# merge multiple input files - If _l_ is given the read that file
          if ! initial then # select next file with earliest log record  
            file_index = 0
            for i in 1 .. @file.size - 1
              file_index = i if @rec[file_index].utime > @rec[i].utime
            end
          end
          throw :new_file if save_index && save_index != file_index && count > 0
          puts "gets: index :#{file_index} count = #{count}" if $options['debug.gets']
# file_index now contains the index of the next file to read from
          r = initial ? @rc.new : @rec[file_index].dup unless @no_look_ahead  
          closed = false
          begin   # loop to collaspe repeated records and handle records with newlines...
            if raw = @file[file_index].gets then
              if $options['max_read_recs'] && @recs > $options['max_read_recs']
                close_lf( file_index )
                return nil 
              end

              @line[file_index] += 1 
              puts "gets: raw initial '#{initial}', count = #{count} #{raw}"  if $options['debug.gets']
#while ignore && 
              if initial
                previous_rec = @rc.new  # null entry
              else
                previous_rec = @rec[file_index].dup if count == 1 && ! @no_look_ahead
              end
              begin  # corrupt offset or eof ??
                @rec[file_index] = @rc.new( raw, @head, @split_p)
              rescue RuntimeError
                redo
              rescue NoMethodError
                warn "NoMethodError file #{@fn[file_index]} type #{@name} #{$!} "
                redo
              end
              next if @rec[file_index].continuation && ! previous_rec # continuation record as first in file -- ignore
              count += 1
              @rec[file_index].fn = @fn[file_index]
              time = @rec[file_index].time if count == 1  # first time

              #  if this record is a continuation record then append the data to previous_rec
              if @rec[file_index].continuation
                r.orec += @rec[file_index].continuation
                puts "gets: continuation:  #{@rec[file_index].continuation}"  if $options['debug.gets']
                redo;  # there may be more than one continuations
              end
              
            else # end of file 
	            puts "gets: end of file #{file_index} count  #{count}"  if $options['debug.gets'] || $options['debug.files']
              if !initial || @closing[file_index] || count != 1 # don't loose last record!
                close_lf( file_index ) 
              else
                @closing[file_index] = true
              end
              closed = true
            end  # gets

            if initial && ! (defined? @rec[file_index].data) then  # corrupt offset value?
              count = 0
	      puts "gets: corrupt record" if $options['debug.gets']
              next
            end

	    if @no_look_ahead   # we have the record just return
	      puts "gets: no_look_ahead return '#{@rec[file_index].data}'" if (defined? @rec[file_index].data) &&  $options['debug.gets']
	      @rec[file_index].count = count if @rec[file_index]
	      return @rec[file_index] 
	    end

	    repeat = ( @rec[file_index].data =~ /^last message repeated (\d+) times/ ||
		      @rec[file_index].data =~ /^Previous message occurred (\d+) times./ )
            if ! closed && repeat
              if initial
                @rec[file_index] = nil
                count = 0
              else
                puts "repeated #{$1}" if $options['debug.gets']
                count += $1.to_i
                @rec[file_index] = previous_rec
              end
            end
          end until (closed || (@rec[file_index] && @rec[file_index].data))

          if $options['debug.gets'] && !repeat && previous_rec
            puts "comparing "
            puts @rec[file_index].log_rec unless closed
            puts previous_rec.log_rec unless closed
          end
        end while (!closed && !repeat && previous_rec &&@rec[file_index].log_rec == previous_rec.log_rec)
      end

      begin
        r.method(:data)    # corrupt offset or eof ??
    	rescue NameError
        return false unless recovering
        @data = 'corrupt record'
      end

      puts "final count #{count}" if $options['debug.gets']
      r.count = count
      if count > 1      
        if ! r.orec  # something broken in the parsing
          STDERR.puts "Parsing problems in line #{@line[file_index]} file #{@fn[file_index]} for host #{@rec[0].h} parser #{@rc}- aborting this file"
          return nil
        end

         r.orec << " -- repeated #{count} times since #{time}"
      end
      
      puts "return '#{r.data}'" if !initial && $options['debug.gets']

      return r unless initial

    end

    def open_lf( fn )


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
        @line = []
      end
      
      $fstate = 'opening'
      if $run_type != 'realtime' && (File.file? off_name) && ! $options['no_offset'] && ! $options['one_file'] 
      	File::open(off_name) { |o|
	        offset = o.gets.to_i
	      }
      end

      if fn.match(/\.gz$/) 
	f = IO.popen("zcat #{fn}")
      else
	f = File.open( fn )
      end
      if f then
	      puts "opened file #{fn} log type #{self}" if $options['debug.split'] || $options['debug.gets'] ||$options['debug.files']
      else
	      puts( STDERR, "failed to open #{fn} #{$!}")
	      return nil
      end
      $fstate = 'seeking'
      f.seek( offset ) if offset
      $fstate = 'reading'
 
      closed = false
      file_index = @file.size
      r = nil
      @file[file_index] = f
      puts "@file[#{file_index}] file #{fn} log type #{self}" if $options['debug.files']
      @closing[file_index] = false
      @fn[file_index] = n
      @line[file_index] = 0
      @off_name[file_index] = off_name

      gets(file_index, nil) unless @no_look_ahead    # to prime the look ahead buffer for finding duplicate records
    end 
    
    def abort
      while @file
	@file[0].seek(0, IO::SEEK_END );
	close_lf( 0 )
      end
    end

# have to drop the look a head!!
    def close_lf( lf = nil )

      puts "closing file  #{lf} log type #{self}" if $options['debug.files']
	offset = @file[lf].tell unless $options['no_write_offset'] ||  $options['no_offset']
	@file[lf].close
	off_n = @off_name[lf]
        
	if @file.size == 1 then  # last one
          @file = nil
	else
          @file.slice!( lf )
          @rec.slice!( lf )
	  @off_name.slice!( lf )
        end

      unless ( $options['no_write_offset'] ||  $options['no_offset'] ) then
	File::open(off_n, 'w') { |o|
	  o.puts offset.to_s
	}
      end
    end

# default log splitter                                                                                                 
    class Record
    attr_reader :count, :time, :utime, :h, :record, :proc, :orec, :data, :int, :fn, :extra_data, :raw, :continuation, :data, :log_rec
    attr_writer :fn, :count

      def initialize(raw=nil, head=nil, split_p=nil, cont=nil)

        @raw = raw
        @split_p = split_p
	@head = head
        @time = nil
        @utime = nil
        @h = nil
        @proc = nil
        @orec = nil
        @log_rec = nil
        @fn = ''
        @data = raw ? '' : 'empty/corrupt'
        @extra_data = ''
	@count = 0
        @continuation = nil
        return unless raw

        if m = raw.match(head) 
          @utime, @time, @h,  @log_rec = m.captures 
          #puts "#{@h}-#{@data}"
          @utime = @utime.to_i
          @data = @log_rec
          split
        else
          raise "Invalid record"
        end

      end

# default log splitter

      def split
        return nil unless @log_rec
	all, p, data = @log_rec.match( @split_p ).to_a

        if ! all  # split failed
	  @orec = @raw
	  @proc = 'none'
	else
	  @data = data ? data : @log_rec
	  if data && ( @data.sub!(/^(pam_\w+\[\d+\]):/, p) || @data.sub!(/^\((pam_\w+)\)/, p) )
	    p=$1
	  end

	  @proc = canonical_proc( p )
	  @orec = "#{@time} #{@h}: #{p}: '#{@data}'"
	end
      end

      def canonical_proc( p )
	p = '' unless p
	if p =~ /last message repeated/ then
	  proc = p
	elsif p =~ /^([-a-zA-Z0-9 ]+)(?:\[(\d+)\])?$/ then  # proc namd[1234]
	  proc = $1
	  pid = $2
	elsif p =~ /^([-a-zA-Z0-9.]+)(?:\[(\d+)\])?$/ then  
	  proc = $1
	  pid = $2
      elsif p =~ /^(\w+)(?:[- 0-9.]+)?(?:\[(\d+)\])?$/ then  # syslogd 1.4.1 
	  proc = $1
	  pid = $2
	elsif p =~ %r|/([^/]+)\[(\d+)\]$| then   #  postfix/smtpd[642]
	  proc = $1
	  pid = $2
	elsif p =~ %r|/([^/]+)$| then   # /usr/bin/sudo
	  proc = $1
	  pid = ''
	elsif p =~ %r!^(\w+)\(\S+\)\[(\d+)\]$! then   # ssh(pam_unix)[899]
	  proc = $1
	  pid = $2
	else
	  proc = ''
	end
	proc.downcase
      end
    end


  end

