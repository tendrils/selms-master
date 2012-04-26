class Wli < LogFile
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
    #WLI_EPRFinanceIntegration: [INFO] [nz.ac.auckland.process.EPRFinancePersonTypeProcess.processFinancePerson] (UoAID:2337651) Person has been sent to Finance successfully
#WLI [INFO] [nz.ac.auckland.timetable.classMeetingPatternPublisher.processes.PublishCombinedSectionMsgProcess.subscription] Start timer based combined section message publishing at 2011/05/30 23:59:00


#      super(  name, /^(\w+):*\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+\(([^)]+)\)\s*(.+)/)

    super(name,fn, /^(\w+):*\s+\[\s*(\w+)\s*\]\s+\[([^\]]+)\]\s+(.+)?/)

    @Tokens = {
        'app' => [String],
        'level' => [Levels],
        'location' => [String]
    }
    @rc = Record
    @no_look_ahead = true
    @count = 0
  end

  def gets(l = nil, raw = nil)
    while (r = super(l)) && !r.level
      l = nil
    end
    return nil unless r

    r.orec = "#{r.time} #{r.h}: #{r.application}: [#{Levels_ar[r.level]}] [#{r.location}] #{r.data}"

    return r

  end

  class Record < LogFile::Record

    attr_reader :time, :utime, :h, :application, :level, :data, :record, :location, :orec
    attr_writer :orec

    def split

      all, @application, @level, @location, d = @data.match(@split_p).to_a
      
      if !all # split failed
        STDERR.puts "failed to split record #{@data} for  #{@fn}"
      end

      if @level && Levels[@level]
        @data = d
      end

      @level = Levels[@level]

      @orec = "#{@time} #{@h}: #{@application}: [#{Levels_ar[@level]}] [#{@location}] #{data}"
    end
  end
end

