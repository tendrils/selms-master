module Procs



  def Procs.pw_check(what=nil, rec=nil )
    @pw_check ||= {}
    case rec
    when 'host'
      return nil if @pw_check.size == 0
      report = ["IPs with login failures on multiple accounts"]
      @pw_check.sort{|a,b| b[1].size<=>a[1].size}.each do |entry|
        ip, upis = entry
        puts "#{ip} #{upis.size}"
        break if upis.size == 1
        report << ip
        upis.each do |upi, count|
#          puts "   #{upi}: #{count}"
          report << "   #{upi}: #{count}"
        end
      end
      return report.size > 1 ? report : []
    when 'test'
    else
      ip, upi = what.split(/\s*,\s*/)
      @pw_check[ip] ||= {}
      @pw_check[ip][upi] ||= 0;
      @pw_check[ip][upi] += 1;

    end
  end

end

