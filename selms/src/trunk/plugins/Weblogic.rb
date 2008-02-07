#
#  this is a example of a logfile plugin that handles logs where one logical record are
# split over several physical records

#1201818959 2008 Feb  1 11:35:59 +13:00 elgo2.itss.auckland.ac.nz: WARN  [nz.ac.auckland.rightnow.KnowledgeBase.getAnswer] RightNow problem
#   first record has a syslog level and a short message
#1201818959 2008 Feb  1 11:35:59 +13:00 elgo2.itss.auckland.ac.nz: fault.api.rightnow.com.RNOWException: acct_login_verify failed
#   next message has more detailed message
#1201818959 2008 Feb  1 11:35:59 +13:00 elgo2.itss.auckland.ac.nz: at api.rightnow.com.RNOWUtil.RunTransaction(RNOWUtil.java:1306)
#   subsequent lines have stack traceback and start with 'at '
#1201818959 2008 Feb  1 11:35:59 +13:00 elgo2.itss.auckland.ac.nz: at api.rightnow.com.RNOWObjectFactory.get(RNOWObjectFactory.java:63)
#............

# We return a record with the first two lines concatenated in data and the rest of the lines in extra_data  

class Weblogic< LogFile

    Levels = { 
       'EMERG' => 0,       #  system is unusable               */
       'ALERT'     => 1,       #  action must be taken immediately */
       'CRITICAL'  => 2,       #  critical conditions              */
       'ERROR'     => 3,       #  error conditions                 */
       'WARN'      => 4,       #  warning conditions               */
       'NOTICE'    => 5,       #  normal but significant condition */
       'INFO'      => 6,       #  informational                    */
       'DEBUG'     => 7        # debug-level messages             */

  }


    def initialize( name, split_p=nil, head=nil)

      super(  name, /^(\w+)\s+(.+)/ )

      @Tokens = {
        'proc' => [ String ],
        'fac'  => [ String ],
        'level' => [ Levels ]
      }
      @rc = Record
      @read_ahead = nil
    end

# weblogic logs are (or can be) multiline -- first line consisting of the actual log message
# followed by subsquent lines that have a traceback

    def gets( l = nil, raw = nil )  # set l for initial read
#      puts "in gets #{l}, #{raw} #{@rec[0]}"
      if !  @rec[0] then   # don't already have first record
	while ( super( 0, raw, TRUE ) )  && ! @rec[0].level   # until start of next record  
	end
	return FALSE if l  # initial call
       end

      return nil unless @rec[0]  # must be at end of file

     r = @rec[0].dup
      while ( open = super( 0, raw, TRUE) )  && ! @rec[0].level   # until start of next record
	if @rec[0].data =~ /^at/  # then trace back
	  r.extra_data += "#{@rec[0].data}\n"
	else
	  r.data += ": #{@rec[0].data}"
	end
      end

      return FALSE unless open

      r.orec = "#{r.time} #{r.h}:  '#{r.data}'"
      pp r if $options['debug.split']
      return r
    end


    class Record < LogFile::Record

      attr_reader :time, :utime, :h, :fac, :level, :data, :record, :proc, :orec, :extra_data
      attr_writer  :extra_data, :data, :orec

#      def initialize(raw=nil, pat=nil, split_p=nil)
#        super(raw, pat, split_p)
#        @extra_data = ''
#        return unless raw
#        all, @utime, @time, @h, @data =  raw.match(pat).to_a
#      end



      def split

        all,  @level, d = @data.match(@split_p ).to_a
        if @level = Levels[@level]
	  @data = d
	  @orec = "#{@time} #{@h}: '#{@data}'"
	end
      end
    end
end
