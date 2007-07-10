# change this if you fiddle with the syslog-ng templates!!!   Should be a global config option??                       

LOG_BITS = /^([^:]+):\s+(.+)?/

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

    def gets

      return nil if ! @file || @file.size == 0

      l = 0
      for i in 1 .. @file.size - 1
	l = i if @rec[l].utime > @rec[i].utime
      end

      r = @rec[l]   # will return this
      # read next record for this file
      
      closed = false
      begin
        if raw = @file[l].gets then
          @lrec[l] = @rec[l].dup unless @rec[l].data =~ /^last message repeat/
          
          @rec[l] = @rc.new( raw, @head, @split_p)
          $c_fn = @off_name[l]
        else # end of file 
          close_lf( l )
          closed = true
        end
      end until closed || (@rec[l] && @rec[l].data )

    if r && r.data =~ /^last message repeated (\d+) times/ then  #
        times = $1
        if @lrec[l] then
          r = @lrec[l].dup
          r.data.sub!(/ : Repeated \d+ times/, '')
          r.data << " : Repeated #{times} times"
        end
	return r
      else
	return r
      end
    end

    def open_lf( fn )

      off_name = fn + '-' + $options['offset'] 
      offset = nil
      
      if !@file then
	@file = []
	@rec = []
	@lrec = []
	@off_name = []
      end
      
      $fstate = 'opening'
      if (File.file? off_name) && ! $options['no_offset'] then
	File::open(off_name) { |o|
	  offset = o.gets.to_i
	}
      end
      f = File.open( fn )
      $fstate = 'seeking'
      f.seek( offset ) if offset
      $fstate = 'reading'
      
      closed = false
      l = @file.size
      r = nil
      begin
        if raw = f.gets
          @file[l] = f
          r = @rc.new( raw, @head, @split_p)
          @rec[l] = r 
          @off_name[l] = off_name
        else
          f.close
          closed = true
        end
      end until closed || (r && r.data )
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
    attr_reader :time, :utime, :h, :record, :proc, :orec, :data, :int

      def initialize(raw, pat, split_p)
        @raw = raw
        @split_p = split_p
        @time = nil
        @utime = nil
        @h = nil
        @proc = nil
        @orec = nil
        @data = nil
        all, @utime, @time, @h,  @data =  raw.match(pat).to_a     
	@utime = @utime.to_i
      end

# default log splitter

      def split
        return nil unless @data
	all, p, @data = @data.match( @split_p ).to_a

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

