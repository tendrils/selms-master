class Osb < LogFile
  # weblogic levels
  Levels = {
      'Emergency' => 0,
      'Alert' => 1,
      'Critical' => 2,
      'Error' => 3,
      'Warning' => 4,
      'Notice' => 5,
      'Info' => 6,
      'Debug' => 7,
      'Trace' => 8
  }

  Levels_ar = ['Emergency', 'Alert', 'Critical', 'Error', 'Warning', 'Notice', 'Info', 'Debug', 'Trace']
  def initialize(name, fn = nil, split_p=nil, head=nil)

    #potential multiline parse of messages like:
    # ####<Jun 25, 2014 3:26:12 PM NZST> <Debug> <ALSB Logging> <ormesbdev01.its.auckland.ac.nz> <WLS_OSB1> <[ACTIVE] ExecuteThread: '39' for queue: 'weblogic.kernel.Default (self-tuning)'> <<anonymous>> <BEA1-26FAFCD2B5F292A3AC26> <d785f59a7feb14f5:-ab9cb83:146cc0d3579:-8000-0000000000049105> <1403666772662> <BEA-000000> < [Logging, Logging_request, Logging, REQUEST] nz.ac.auckland.osb.jmsmigration.eprperson: Publishing the EPR Person messsage to the local JMS topic for: 6763439
    # stack trace 1
    # stack trace 2
    # stack trace 3>
    super(name,fn, /([^:]*): ####<([^>]*)> <([^>]*)> <([^>]*)> <([^>]*)> <([^>]*)> <([^>]*)> <<([^>]*)>> <([^>]*)> <([^>]*)> <([^>]*)> <([^>]*)> < \[([^\]]*)\] ([^:]*): (.*)/, nil, /^13[^0-9]{8}/ )

    @Tokens = {
        'server' => [String],
        'date' => [String],
        'level' => [Levels],
        'subsystem' => [String],
        'machine' => [String],
        'managedServer' => [String],
        'thread' => [String],
        'user' => [String],
        'txId' => [String],
        'diagnosticContextId' => [String],
        'timestamp' => [String],
        'messageId' => [String],
        'osblocation' => [String],
        'osblogger' => [String],
        'data' => [String]
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

    attr_reader :time, :utime, :h, :server, :date, :level, :subsystem, :machine, :managedServer, :thread, :user, :txId, :diagnosticContextId, :timestamp, :messageId, :osblocation, :osblogger, :data, :record, :orec
    attr_writer :orec, :data

    def split
      all, @server, @date, @level, @subsystem, @machine, @managedServer, @thread, @user, @txId, @diagnosticContextId, @timestamp, @messageId, @osblocation, @osblogger, @data= @log_rec.match(@split_p).to_a
      unless all # split failed
        @orec = @log_rec
        @data = ""
        return
      end

      @level = Levels[@level]
      @orec = "#{@time} #{@h}: #{@server}: ####<#{@date}> <#{@level}> <#{@subsystem}> <#{@machine}> <#{@managedServer}> <#{@thread}> <<#{@user}>> <#{@txId}> <#{@diagnosticContextId}> <#{@timestamp}> <#{@messageId}> < [#{@osblocation}] #{@osblogger}: #{@data}>"
    end
  end
end
