class LogFile

  class Snare::Gulp < Snare

  end

  class Base::Gulp < Base

  end

end

class Action

  class Gulp < Base
    def produce_reports(processed_hosts)
      pp processed_hosts
    end

  end
end