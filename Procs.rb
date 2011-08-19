module Procs


  @pw_check = []
  def Procs.pw_check(what=nil, rec=nil )
    if rec
      ip, upi = what.split(/\s*,\s*/)
      @pw_check[ip] ||= {}
      @pw_check[ip][upi] += 1;
    else
      @pw_check.sort{|a,b| b[1].size<=>a[1].size}.each do |entry|
        ip, upis = entries
        puts ip
        uips.each do |upi, count|
          puts "   #{upi}: #{count}"
        end
        if
      end
    end
  end

end

