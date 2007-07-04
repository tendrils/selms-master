

class Cisco < LogFile
    attr_reader  :Tokens


    def initialize(name, split_p=nil, head=nil)

      super(name, split_p || /^(\d+)?[^%]+(%(\w+)-(\d)-(\S+):.+)?/  )

      @Tokens = {
	'cat'    => [String, 'options'],
	'event'  => [String],
	'level'  => [Integer],
      }

      @rc = Record
    end


    class Record

      attr_reader :time, :utime, :h, :cat, :event, :level, :record, :orec, :data

      def initialize(raw, pat, split_p)
        @raw = raw
        @split_p = split_p
        @h = nil
        @proc = nil
        @orec = nil
        @rest = nil
        all, @utime, @time, @h, @data =  raw.match(pat).to_a
      end


      def split
	all, @proc, @rec, @cat, @level, @event = @data.match(@split_p ).to_a
	@level = @level.to_i
	@orec = "#{@time} #{@h}: '#{@data}'"
      end
    end
end

class Ciscowlan < Cisco

   def initialize(name, split_p=nil, head=nil)
     super( name, /^(\S+) ((\w+)-(\d)-(\S+):.+)?/ )
   end
end
