# apache.rb
# 12 July 2007
#

class Apache < LogFile
  
  def initialize( name=nil, split_p=nil, head=nil)
    
    super( name, split_p, head )

    @Tokens = {
     'source'    => [String],
      'client'  => [String],
      'user'  => [String],
      'a_time'  => [String],
      'request'  => [String],
      'status'  => [Integer],
      'bytes'  => [String],
      'referer'  => [String],
      'user_agent'  => [String],
      'cookies'  => [String]
    }

    @rc = Record

  end
  
  class Record < LogFile::Record 
    attr_reader :time, :utime, :h, :record, :proc, :orec, :data, :source, :user, :client, :a_time, 
                :fn, :url, :status, :bytes, :referer, :user_agent, :cookies, :request
    attr_writer :fn

      def initialize(raw=nil, pat=nil, split_p=nil)

        @raw = raw
        @split_p = split_p
        @pat = pat
        @time = nil
        @utime = nil
        @h = nil
        @proc = nil
        @orec = nil
        @fn = ''
        @data = ''
        return unless raw
        all, @utime, @time, @h,  @data =  raw.match(pat).to_a 
	@utime = @utime.to_i
      end

# default log splitter

      def split
        
        @orec = "#{@time} #{@h}: '#{@data}'"
        
        return nil unless @data
	server, @source, @client, @user, rest = @data.split(/\s+/, 5)
     puts @raw unless rest
        return unless rest
        rest.sub!(/^\[([^\]]+)\] /, '')
        @a_time = $1
        rest.sub!(/^"([^"]+)" /, '')
        @request = $1
        return unless @request
        @status, @bytes, rest = rest.split(/\s+/, 3)
        @status = @status.to_i
        @bytes= @bytes.to_i
   puts @raw unless rest
        return unless rest
         rest.sub!(/^"([^"]+)" /, '')
        @referer = $1
         rest.sub!(/^"([^""]+)" /, '')
        @user_agent = $1
         rest.sub!(/^"(["]+)" /, '')
        @cookie = $1
        true
      end
  end
end


