

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


    def initialize( name, fn=nil, split_p=nil, head=nil)

      super(  name, fn, /^([^:]+):\s+\[ID \d+ (\w+)\.(\w+)\]\s*(.+)/ )

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

        all, p, @fac, @level, @data = @data.match(@split_p ).to_a
	@proc = canonical_proc( p )
        @level = Levels[@level]
        @orec = "#{@time} #{@h}: #{@proc}: '#{@data}'"
      end
    end
end
