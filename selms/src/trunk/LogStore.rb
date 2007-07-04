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

    def traverse
      Find.find( @root ) { |filename|

	mach = $1 if filename =~ %r|^#{@root}/([^/]+)|o;

	next if ! mach

	mach.sub!(/\.#{$options['hostdomain']}$/o, '') if $options['hostdomain']

	if $options['one_host'] && $options['one_host'] != mach then 
	  Find::prune
	  return;
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


