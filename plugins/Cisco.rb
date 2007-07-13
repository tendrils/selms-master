

class Cisco < LogFile

    def initialize(name, split_p=nil, head=nil)

      super(name, split_p || /^(\d+)?[^%]+(%(\w+)-(\d)-(\S+):.+)?/  )

      @Tokens = {
	'cat'    => [String, 'options'],
	'event'  => [String],
	'level'  => [Integer],
      }

      @rc = Record
    end


    class Record < LogFile::Record

      attr_reader  :cat, :event, :level, :fn

      def initialize(raw=nil, pat=nil, split_p=nil)
        super(raw, pat, split_p)
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
