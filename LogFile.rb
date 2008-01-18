# change this if you fiddle with the syslog-ng templates!!!   Should be a global config option??                       

LOG_BITS = /^([^:]+):\s+(.+)?/
# token change
  class LogFile 
    attr_reader  :Tokens, :name, :rec, :file 

    def initialize( name=nil, split_p=nil, head=nil)

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
      @rc = Record
    end

    def gets( l = nil, raw = nil )  # set l for initial read

      if $run_type == 'realtime'
#        raw = $rt_fh.gets
        return @rc.new( raw, @head, @split_p)
      end
      return nil if ! @file || @file.size == 0

      initial = l
      previous_rec = nil
      count = 0  # number of duplicates  
      r = nil   # define out side loop
      time = 0
      
      puts "initial #{l}" if initial && $options['debug.gets']
      
      catch :new_file do
        begin  # loop while records are the same
          save = l
          if ! initial then # select next file with earliest log record  
            l = 0
            for i in 1 .. @file.size - 1
              l = i if @rec[l].utime > @rec[i].utime
            end
          end
          throw :new_file if save && save != l && count > 0
          puts "index :#{l}" if $options['debug.gets']
          
          r = initial ? @rc : @rec[l].dup 
          
          closed = false
          begin
            if raw = @file[l].gets then
              count += 1
              puts "raw #{count} #{raw}"  if $options['debug.gets']
              if initial
                previous_rec = @rc.new  # null entry
              else
                puts "not initial #{count}" if $options['debug.gets']
                previous_rec = @rec[l].dup if count == 1
              end
              @rec[l] = @rc.new( raw, @head, @split_p)
              time = @rec[l].time if count == 1  # first time
              @rec[l].fn = @fn[l]
#              puts "filename #{@rec[l].fn}"
            else # end of file 
              #puts "end of file #{l} count  #{count} #{@lrec[l]}"
              if initial || @closing[l] || count != 1 # don't loose last record!
                close_lf( l ) 
                #              puts "closing file #{l}"
              else
                @closing[l] = true
              end
              closed = true
            end

            if initial && ! defined? @rec[l].data then  # corrupt offset value?
              count = 0
              next
            end

            if ! closed && ( @rec[l].data =~ /^last message repeated (\d+) times/ ||
			    @rec[l].data =~ /^Previous message occurred (\d+) times./ )
              if initial
                @rec[l] = nil
                count = 0
              else
                puts "repeated #{$1}" if $options['debug.gets']
                count += $1.to_i 
                @rec[l] = previous_rec
              end
            end
          end until ( closed || (@rec[l] && @rec[l].data )) 
          
          if $options['debug.gets']
            puts "comparing" 
            puts @rec[l].data unless closed
            puts previous_rec.data  unless closed
          end
        end while ( ! closed &&  @rec[l].data == previous_rec.data )
      end

      if count > 1      
         r.data << " -- repeated #{count} times since #{time}"
      end
      
      puts "return '#{r.data}'" if !initial && $options['debug.gets']
      
      return r unless initial

    end

    def open_lf( fn )

      if $run_type != 'realtime'
        off_name = fn + '-' + $options['offset'] 
        fn =~ /.+\/(.+)/
        n = $1
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
      if $run_type != 'realtime' && (File.file? off_name) && ! $options['no_offset'] then
	File::open(off_name) { |o|
	  offset = o.gets.to_i
	}
      end

      f = File.open( fn )
      if f then
	puts "file #{fn} offset #{offset}" if $options['debug.split'] || $options['debug.gets']
      else
	puts( STDERR, "failed to open #{fn} #{$!}")
	return nil
      end
      $fstate = 'seeking'
      f.seek( offset ) if offset
      $fstate = 'reading'
 
      closed = false
      l = @file.size
      r = nil
      puts "open #{l}: #{fn}" if $options['debug.files']
      @file[l] = f
      @closing[l] = false
      @fn[l] = n
      @off_name[l] = off_name
      gets(l) 
    end 
    
    def abort
      while @file
	@file[0].seek(0, IO::SEEK_END );
	close_lf( 0 )
      end
    end

# have to drop the look a head!!
    def close_lf( lf = nil )

	offset = @file[lf].tell
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
    attr_reader :time, :utime, :h, :record, :proc, :orec, :data, :int, :fn
    attr_writer :fn

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
        return unless raw
        all, @utime, @time, @h,  @data =  raw.match(pat).to_a 
	@utime = @utime.to_i
      end

# default log splitter

      def split
        return nil unless @data
	all, p, @data = @data.match( @split_p ).to_a
        
        if data && ( @data.sub!(/^(pam_\w+\[\d+\]):/, p) || @data.sub!(/^\((pam_\w+)\)/, p) )
          p=$1
        end

	@proc = canonical_proc( p )
      
	@orec = "#{@time} #{@h}: #{p}: '#{@data}'"

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

