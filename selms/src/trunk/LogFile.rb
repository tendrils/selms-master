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

      l = nil  # index for @file array

      if @file.class == File then  # just a single file...
	if raw = @file.gets
	  @lrec = @rec.dup unless @rec.data =~ /^last message repeat/
	  r = @rec = @rc.new( raw, @head, @split_p)
	else
	  close
	  return nil
	end
      else  # must be an array -- need to merge inputs
	# find file with lowest time
	l = 0
	for i in 1 .. @file.size - 1
	  l = i if @rec[l].utime > @rec[i].utime
	end

	r = rec[l]   # will return this
	# read next record for this file
	if raw = @file[l].gets then
	  @lrec[l] = @rec[l].dup unless @rec[l].data =~ /^last message repeat/
	  @rec[l] = @rc.new( raw, @head, @split_p)
	  $c_fn = @off_name[l]
	else # end of file
	  close( l )
	end
      end

      if r && r.data =~ /^last message repeated (\d+) times/ then  #
	r = (l ? @lrec[l] : @lrec).dup
	r.data << " : Repeated #{$1} times"
	return r
      else
	return r
      end
    end

    def open_lf( fn )

      off_name = fn + '-' + $options['offset'] 
      offset = nil
      
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
      if !@file then
	@file = f
	@lrec = nil
	@off_name = off_name
	$c_fn = fn
      else
	if @file.class == File then
	  f1 = @file
	  n1 = @off_name
	  @rec = []
	  @lrec = []
	  @file = []
	  @off_name = []
	  @rec.push( @rc.new( f1.gets, @head, @split_p) )
	  @file.push( f1 )
	  @off_name.push( off_name )
	end
	@file.push( f )
	@off_name.push( fn )
	@rec.push( @rc.new( f.gets, @head, @split_p) )
      end
    end

    def abort

      if @file == File then
	@file.seek(0, IO::SEEK_END );
	@file.close
      else
	@file.each{ |file|
	  file.seek(0, IO::SEEK_END );
	  file.close
	}
      end

    end


    def close( lf = nil )
      if lf then
	offset = @file[lf].tell
	@file[lf].close
	off_n = @off_name[lf]

	if @file.size == 2 then  # only one file left ...
	  x = lf == 0 ? 1 : 0
	  @file = @file[x]
	  @rec = @rec[x]
	  @off_name = @off_name[x]
	else
	  @file.slice!( lf )
	@rec.slice!( lf )
	  @off_name.slice!( lf )
	end
      else
	offset = @file.tell
	@file.close
	off_n = @off_name
        @file = nil
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
#puts @raw
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

