module Procs



  def Procs.pw_check(what=nil, rec=nil )
    @pw_check ||= {}
    case rec
    when 'host'
      return if @pw_check.size == 0
      @pw_check.sort{|a,b| b[1].size<=>a[1].size}.each do |entry|
        ip, upis = entry
        puts ip
        upis.each do |upi, count|
          puts "   #{upi}: #{count}"
        end
      end
    when 'test'
    else
      ip, upi = what.split(/\s*,\s*/)
      @pw_check[ip] ||= {}
      @pw_check[ip][upi] += 1;
    end
  end

end

