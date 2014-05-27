class EsbLogs < LogStore

  def initialize(root, time = Time.now)
 
    super(root, time = Time.now)
    @no_look_ahead = true
  end

    def type_of_host( dir )
      'esb'
    end
end
