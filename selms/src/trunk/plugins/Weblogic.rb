

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
    end

    class Record < LogFile::Record

      attr_reader :time, :utime, :h, :fac, :level, :data, :record, :proc, :orec

      def initialize(raw=nil, pat=nil, split_p=nil)
        super(raw, pat, split_p)
#        return unless raw
#        all, @utime, @time, @h, @data =  raw.match(pat).to_a
      end



      def split

        all,  @level, @data = @data.match(@split_p ).to_a
        @level = Levels[@level]
        @orec = "#{@time} #{@h}: '#{@data}'"
      end
    end
end
