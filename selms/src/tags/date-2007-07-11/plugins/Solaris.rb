

class Solaris < LogFile

    Levels = { 
       'emerg' => 0,       #  system is unusable               */
       'alert'     => 1,       #  action must be taken immediately */
       'critical'  => 2,       #  critical conditions              */
       'error'     => 3,       #  error conditions                 */
       'warning'   => 4,       #  warning conditions               */
       'notice'    => 5,       #  normal but significant condition */
       'info'      => 6,       #  informational                    */
       'debug'     => 7        # debug-level messages             */

  }

    attr_reader  :Tokens


    def initialize( name, split_p=nil, head=nil)

      super(  name, /^([^:]+):\s+\[ID \d+ (\w+)\.(\w+)\]\s*(.+)/ )

      @Tokens = {
        'proc' => [ String ],
        'fac'  => [ String ],
        'level' => [ Levels ]
      }
      @rc = Record
    end

    class Record < LogFile::Record

      attr_reader :time, :utime, :h, :fac, :level, :data, :record, :proc, :orec

      def initialize(raw, pat, split_p)
        @raw = raw
        @split_p = split_p
        @time = nil
        @utime = nil
        @h = nil
        @record = nil
        @proc = nil
        @orec = nil
        @rest = nil
        all, @utime, @time, @h, @data =  raw.match(pat).to_a
      end



      def split

        all, p, @fac, @level, @data = @data.match(@split_p ).to_a
	@proc = canonical_proc( p )
        @level = Levels[@level]
        @orec = "#{@time} #{@h}: #{@proc}: '#{@data}'"
      end
    end
end
