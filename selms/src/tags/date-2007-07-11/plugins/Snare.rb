class Snare < LogFile

  def initialize(name=nil)
    super(name)
    @Tokens = {
      'criticality' => [Integer ],
      'source'   => [ String ],
      'snareec'  => [ String ],
      'eventid'  => [ Integer ],
      'source2'  => [ String ],
      'user'     => [ String ],
      'sid'      => [ String ],
      'logtype'  => [ String ],
      'name'     => [ String ],
      'category' => [ String ],
    }
    @rc = Record
  end


  def open( fn )      
    @file = File.open( fn )
  end

# default log splitter                                                                                                 
  class Record
    attr_reader :time, :utime, :h, :rec, :orec, :data, :criticality, :source, :snareec, :eventid, :source2, :user, :sid, :logtype, :name, :category 

    def initialize( raw, pat, dnmmy = nil )
      @raw = raw
      
      @time = nil
      @utime = nil
       @h = nil
      @orec = nil
      @data = nil
      all, @utime, @time, @h,  @data =  raw.match(pat).to_a

    end
    
# default log splitter

    def split
#pp data
      lt, @criticality, @source, @snareec, dt, @eventid, @source2, @user, @sid,
	@logtype, @name, @category, xx, s, es  = @data.split("\t")
#puts data unless s
      s = '' unless s
      es = '' unless es
      @data = (s + ' ' + es).sub(/^\s+/, '')

      @criticality = @criticality.to_i
      @eventid = @eventid.to_i
      @orec = "#{@time} #{@h}: #{@snareec}: #{@category}: #{@user}: #{@eventid}: #{@source}: '#{@data}'"
    end
  end
end

