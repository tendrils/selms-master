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
class LogFile


  class Weblogic < Base

      Levels = {
         'emerg' => 0,       #  system is unusable               */
         'alert'     => 1,       #  action must be taken immediately */
         'critical'  => 2,       #  critical conditions              */
         'error'     => 3,       #  error conditions                 */
         'warn'      => 4,       #  warning conditions               */
         'notice'    => 5,       #  normal but significant condition */
         'info'      => 6,       #  informational                    */
         'debug'     => 7        # debug-level messages             */

    }
    Levels_ar = [ 'EMERG', 'ALERT', 'CRITICAL', 'ERROR', 'WARN', 'NOTICE', 'INFO', 'DEBUG' ]

      def initialize( name=nil, fn=nil, split_p=nil, head=nil)

        super(  name, fn=nil, /^(\w+)\s+\[([^\]]+)\]\s*(.+)/ )

        @Tokens = {
          'proc' => [ String ],
          'fac'  => [ String ],
          'level' => [ Levels ]
        }
        @rc = Record
        @no_look_ahead = true
        @count = 0
      end

  # weblogic logs are (or can be) multiline -- first line consisting of the actual log message
  # followed by subsquent lines that have a traceback

      def gets( l = nil, raw = nil )  # set l for initial read

  #pp  @rec[0]

        puts "in Weblogic gets l = #{l}, raw=#{raw} "  if $options['debug.gets']

        while ( r = super( l ) ) && ! r.level   # until start of next record
          l = nil
        end
        return nil unless r # not_eof # unless (defined? @rec[0].level or (defined? @rec[0]) &&  (defined? @rec[0].data ) && @rec[0].data)  # must be end of file

  #        r = @rec[0]
  #	if m = r.data.match( /(.+) +(StackTrace: .+)/).to_a
  #        if ! r.data.match( /^[A-Z]+/)
  #	  r.data += ": #{m[1]}"
  #	  r.extra_data += "#{m[2]}\n"
  #	end

  # pp r unless r.level

        r.orec = "#{r.time} #{r.h}: #{Levels_ar[r.level]} [#{r.proc}] '#{r.data}'"
  #      r.orec = "#{r.time} #{r.h}:  '#{r.data}'"
        pp r if $options['debug.split']
        return r

      end


      class Record < Base::Record

        attr_reader :time, :utime, :h, :fac, :level, :data, :record, :proc, :orec, :extra_data
        attr_writer  :extra_data, :data, :orec

        def split

          @level, @proc, d = @data.match(@split_p ).captures

          if @level and @level = Levels[@level.downcase]
            @data = d
          end
        end
      end
  end
end