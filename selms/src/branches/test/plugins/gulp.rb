class Gulp
  # To change this template use File | Settings | File Templates.



  class Record::Snare < LogFile::Record
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