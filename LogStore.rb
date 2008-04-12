  class LogStore
    LOG_HEAD = /(\d+) (\d{4} \w{3}\s+\d+ [:0-9]+ (?:\+|-)\d\d:\d\d) ([^:]+):\s*(.+)/

    attr_reader :log_head

    def initialize( root, time = Time.now )
      @root = root
      @year = time.strftime("%Y")
      @month = time.strftime("%m")
      @day = time.strftime("%d")
      @log_head = LOG_HEAD
    end

    def extract_rt_host( log ) 
      r = log.split(/\s+/)
      return r[6].chop
    end
    
    def traverse

      if $options['one_file']  # just a single file this run
	@done = true
	yield $options['one_file'], $options['one_host'] 
      end

      return nil if defined? @done

      Find.find( @root ) { |filename|

	mach = $1 if filename =~ %r|^#{@root}/([^/]+)|o;

	next if ! mach

	mach.sub!(/\.#{$options['hostdomain']}$/o, '') if $options['hostdomain']

	if $options['one_host'] && 
            ( ( $options['one_host'].class == String && $options['one_host'] != mach) ||
             ( ! $options['one_host'].match( mach ) ) ) then 
	  Find::prune
	end

	rest = $1 if filename =~ %r|^#{@root}/[^/]+/(.*)|o;
	next unless  rest;
	if rest =~ %r|^(\d{4})-(\d\d)$| then
	  Find.prune if  ($1 != @year or $2 != @month )
	  next
	elsif  rest =~ %r|^\d{4}-\d\d/(\d\d)$| then
	  if  $1 != @day then
	    Find.prune  
	    next;
	  end
	end

	yield filename, mach
      }
    end

    def type_of_host( dir ) 

      Dir.new(dir).each { |f|
	return 'cisco' if f =~ /^local0/;
	return 'windows' if f =~ /^user/;
      }
      return 'unix'
    end
  end


