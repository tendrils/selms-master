class Esb < LogFile
  # log4j levels
  Levels = {
      'FATAL' => 0,
      'ERROR' => 1,
      'WARN' => 2,
      'INFO' => 3,
      'DEBUG' => 4,
      'TRACE' => 5
  }

  Levels_ar = ['FATAL', 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE']
   
  def initialize(name, fn = nil, split_p=nil, head=nil)

    #should parse something along the lines of:
    #APP: [LEVEL] [PROGRAM_LOCATION] DATA
    #e.g.:
    #ESB_StudentAdminSubscribers: [INFO ] [nz.ac.auckland.integration.messaging.subscription.filtering.FilteredMessageSubscriber.UOAJMSServer_2@nz.ac.auckland.jms.identity.person.StudentAdminPerson] The Identity Person message for 4051614 has been sent for the subscriber: StudentAdminPerson, target context: StudentAdminPerson

    super(name,fn, /^(\w+):*\s+\[\s*(\w+)\s*\]\s+\[([^\]]+)\]\s+(.+)?/, nil, /^13[^0-9]{8}/ )

    @Tokens = {
        'app' => [String],
        'level' => [Levels],
        'location' => [String]
    }
    @rc = Record
    @count = 0
  end

  def gets(l = nil, raw = nil, c = false)

    while (r = super(l)) && !r.level
      l = nil
    end
    return nil unless r

    return r

  end

  class Record < LogFile::Record

    attr_reader :time, :utime, :h, :application, :level, :data, :record, :location, :orec
    attr_writer :orec, :data

    def split

      all, @application, @level, @location, d = @log_rec.match(@split_p).to_a
      
      if !all # split failed
        STDERR.puts "failed to split record #{@log_rec} for  #{@fn}"
      end
      @h = @application
      if @level && Levels[@level]
        @data = d
      end

      @level = Levels[@level]

      @orec = "#{@time} #{@h}: #{@application}: [#{Levels_ar[@level]}] [#{@location}] '#{data}'"
    end
  end
end

