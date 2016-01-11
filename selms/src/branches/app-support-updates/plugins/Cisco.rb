

class Cisco < LogFile

	def initialize(name, fn=nil, split_p=nil, head=nil)

		# Cx-Beta-Wism-controller-A: *spamReceiveTask: Aug 16 07:50:04.616: %OSAPI-5-OSAPI_INVALID_TIMER: timerlib.c:542 Failed to retrive timer.

		#      split_p = /^(\d+)?[^%]*(%(\w+)-(\d)-(\S+):.+)?/ unless split_p
		split_p = /^(\d+)?[^%]*(%(\w+)-(\d)-(\S+):.+)?/ unless split_p

		super(name, fn, split_p  )

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
			# hack because there are two formats of log record :(
			if ! @cat
				@cat = 'XXX'
				@level = 6
				@event = ''
			elsif@proc == ':'
				@level = '3'
				@event = ''
				all, @cat, @proc, @event = @data.match(/^: \[(\w+)\] ([^:]+):/ ).to_a
			end
			@level = @level.to_i
			@orec = "#{@time} #{@h}: '#{@data}'"
		end
	end
end

class Ciscowlan < Cisco

	def initialize(name, fn=nil, split_p=nil, head=nil)
		super( name, fn, /(\S+) ((\w+)-(\d)-(\S+):.+)?/ )
	end

	class Record < Cisco::Record
	end
end
