class Gulp
  # To change this template use File | Settings | File Templates.
  class Record  < LogFile::Record

  end



  class Record::Snare  < Record
    attr_reader :saddr, :upi, :service
    def split
      super
      case @eventiid
        when 580

        else

      end

    end

    def post_gulp
    end

  end
end

class Action

  class Gulp < Base
    def produce_reports(processed_hosts)
  pp processed_hosts
    end

  end
end