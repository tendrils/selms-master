module Procs


  def pw_check(what=nil, rec=nil )
    @pw_count ||= {}

    case rec
    when 'host'
      return [] if @pw_count.size == 0
      report = ["\n   IPs with login failures on multiple accounts\n"]
      @pw_count.sort{|a,b| b[1].size<=>a[1].size}.each do |entry|
        ip, upis = entry
        break if upis.size == 1
        report << "    #{ip}:"
        upis.each do |upi, count|
          report << "       #{upi}: #{count}"
        end
      end
      return report.size > 1 ? report : []
    when 'test'
    else
      upi, ip = what.split(/\s*,\s*/)
      return if ip == '' || ip.match(/^(UXCHANGE10|ECAD)/)
      @pw_count[ip] ||= {}
      @pw_count[ip][upi] ||= 0;
      @pw_count[ip][upi] += 1;
    end
  end

end

