class RunType

  def initialize

    # define a new class for each host.  The class inheirits from Host and                                                       
    # defines host specific scanning and alerting methods                                                                        

    $run = self
    @action_classes={}
    @hosts = {}
    @buckets = {}
    @counters = {}
    @host_patterns = {}
    
  end


end
