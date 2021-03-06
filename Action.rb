require 'net/smtp'
class Action

  class Base

    def test
      ''
    end

    def initialize
      $tagged = {}
    end

# default alert/warning routines...

    def do_periodic (type, host, file, msg, extra = nil )
      r = host.recs[type] = [] unless r = host.recs[type]
      r << msg
    end

    def do_realtime (type, host, file, msg)
      host.recs[type] << msg
    end

    def async_send(host, type, file, data)
    end

    def produce_reports(processed_hosts)

    end

    public :test
  end

  class Email < Action::Base

    def initialize
      super
    end

    def do_periodic (type, host, file, msg, extra = nil )
      em = ''
      if extra
      extra.split(/\s*,\s*/).each do |option|
          case option
          when /^notify:\s*(.+)/ # email
            em = "-#{$1}"
          when/^count:\s*(\d+)-(\d+)\s+(\S+)\s+(\S+)\s*/
	    $tagged['count'] ||= {}
            $tagged['count'][$4] ||= []
            $tagged['count'][$4][0] ||= {}

	    unless $tagged['count'][$4][0][host.name]
	      $tagged['count'][$4][0][host.name] = []
	      $tagged['count'][$4][0][host.name][0] = ""
	      $tagged['count'][$4][0][host.name][1] = 0
	      $tagged['count'][$4][0][host.name][2] = $3
	    end
 
	    $tagged['count'][$4][1] = $2.to_i
	    $tagged['count'][$4][0][host.name][1] += 1
	    if $tagged['count'][$4][0][host.name][1] >= $1.to_i
	    	$tagged['count'][$4][0][host.name][0] = "#{msg},\tCOUNTED:#{$tagged['count'][$4][0][host.name][1]}"
	    end
          end 
        end
      elsif host.file[file] && host.file[file]['email']
        em = "-#{host.file[file]['email']}"
      end
      r = host.recs[type+em] = [] unless r = host.recs[type+em]
      r << msg

      # For wli applications do something special
      # For wli applications do something special
      if host.name =~ /_wli_/
        $tagged['UoAID'] ||= {}
        $tagged['UoAID'][host.email] ||= {}
        $tagged['UoAID'][host.email][host.name] ||= []

        if msg =~ /UoAId(.*?)(\d+)/i
          $tagged['UoAID'][host.email][host.name] << "#{$2}"
        end
      end
    end

    def do_realtime (type, host, msg, file, rec = nil)
      if $bucket[type] then
        data = $bucket[type]
      else
        data=[]
        data << (msg || rec)
      end
      async_mail(host, type, data)
    end

    def async_send(host, type, data)
      async_mail(host, type, data)
    end

    def async_mail(host, type, data)
      $threads.push Thread.new {
        smtp = Mail.new($options['mail_server'], "SELMS <#{$options['mail_from']}>")

        begin
#	smtp.send( host.email, "SELMS #{type} from #{host.name}", data )
          smtp.send('r.fulton', "#{host.email} - #{host.name}", data)
        rescue
        end

        smtp.finish if smtp
      }
    end


    def produce_reports(processed_hosts)

      # go through the hosts and build reports for each reporting address

      reports = {} # indexed by reporting address
      processed_hosts.each { |host, count| # each host we have logs to report for
      # skip unless we have something to report

        c = 0
        host.recs.each { |key, recs |
          c += recs.size
        }

        next unless c > 0 || host.count.size > 3;

        def_who = (host.email || 'default').strip
        def_who = def_who.split(/\s*,\s*\**/).map { |addr| 'email:' + addr }
        name = host.name
        host.recs['warn'].size

#pp host.count

        # merge warnings and alters so we can put these all at the top of the report
        if host.count.size > 0 then # more than the default counts
          summ = []
          host.count.sort.each { |k, v|
            case v.label
              when 'Number of dropped records', 'Number of ignored records'
              else
                summ << "    #{v.label} = #{v.val}" if v.val > v.thresh
            end
          }
          if host.recs['post']
            host.recs['post'].each do |rec|
              summ << "    #{rec}"
            end
          end
          host.recs.delete('post')

          if summ.size > 0 then
            def_who.each { |w|
              reports[w] = {} unless reports[w]
              reports[w]['summ'] = {} unless  reports[w]['summ']
              reports[w]['summ'][name] = summ
            }
          end
        end


        host.recs.each { |t, recs|
          next unless recs and recs.size > 0
	  count = false
          all, type, email = t.match(/(\w+)-?(.+)?/).to_a
          if  email
	    who = email.split(/\s*,\s*\**/).map { |addr| 'email:' + addr }
          else
            who = def_who
          end
          who.each { |w|
            reports[w] ||= {}
            reports[w][type] ||= {}
            reports[w][type][name] ||= []
            recs.each { |rec|
	      reports[w][type][name] << rec
              if reports[w][type][name].size > $options['max_report_recs']
                reports[w][type][name] << "***** output truncated *****\n"
                break
              end
            }
          }
        }
      }
      
      # Do stuff for tagged array.
      if $tagged.has_key?('count')
        $tagged['count'].each { |who, val|
	  if val[0].length >= val[1]
	    val[0].each { |host, val|
	      reports["email:#{who}"] ||= {}
	      reports["email:#{who}"]["tagged-#{val[2]}"] ||= {}
	      reports["email:#{who}"]["tagged-#{val[2]}"][host] ||= []
	      reports["email:#{who}"]["tagged-#{val[2]}"][host][0] = val[0]
	    }
	  end
        }
      end
      
      if $tagged.has_key?('UoAID')
	$tagged['UoAID'].each { |who, app|
	  app.each { |host, id|
	     reports["email:#{who}"] ||= {}
             reports["email:#{who}"]["tagged-UoAID-to-Republish"] ||= {}
             reports["email:#{who}"]["tagged-UoAID-to-Republish"][host] ||= []
             reports["email:#{who}"]["tagged-UoAID-to-Republish"][host] << id
	  }
	}
      end      


      # now send the reports to each address
      if $options['no_mail'] && !$options['mail_to'] then
        $options['outfile'] = '-'
      end

      if $options['outfile'] then
        of = $options['outfile'] == '-' ? STDOUT : File.open($options['outfile'], 'w');
      end

      if !$options['no_mail'] || $options['mail_to'] then
	begin
          smtp = Mail.new($options['mail_server'], "SELMS <security-alert@auckland.ac.nz>")
	rescue
	  STDERR.puts "mail  coonection to #{$options['mail_server']} failed: $!" 
	  of = STDOUT
	  no_mail = true
	end
      end

      reports.each { |who, rep|
        report = []
	rep.keys.select{ |i| 
	  if i =~ /tagged-(\S*)/ 
	    list_recs(report, rep["tagged-#{$1}"], $1.capitalize)
	  end
	}
        list_recs(report, rep['alert'], "Alerts") if  rep['alert']
        list_recs(report, rep['warn'], "Warnings") if  rep['warn']
        list_recs(report, rep['summ'], "Summary") if  rep['summ']
        list_recs(report, rep['post'], "post process report") if  rep['post']
        list_recs(report, rep['report'], "Unusual Records") if rep['report']

# loop over destinations for report

#	who.each{ |dest |
        dest = who
        no_mail = $options['no_mail']
        subject = "#{$options['mail_subject']} for #{dest}"
        subject << " for #{dest}" if no_mail
        type, address = dest.split(/:/)
        if $options['outfile'] then
          of.puts "\n\n\n"
          of.puts "\t\t\t\t#{'*'*dest.length}"
          of.puts "\t\t\t\t#{dest}"
          of.puts "\t\t\t\t#{'*'*dest.length}"
          of.puts report.join("\n")
        end
        case type
          when 'email'

            if !no_mail || !$options['mail_to'] then
              to = address
              if $options['mail_to'] then
                if no_mail then
                  to = $options['mail_to']
                  no_mail = false
                else
                  to << ", #{$options['mail_to']}"
                end
              end
              begin
                smtp.send(to, subject, report)
              rescue
              end
            else
              STDERR.puts "No mail addresses for output"
            end
          else
            STDERR.puts "Unknown reporting type '#{type}'"
        end
#	}
      }
      smtp.finish if smtp

    end

    def list_recs(report, list, label, summary=nil)

      report << "             #{'='* label.length}"
      report << "             #{label}"
      report << "             #{'='* label.length}"

      list.each { |host, list|
#puts "null list for #{host}" unless list[0]
        next unless list and list[0] and list[0].size > 0
#        next unless list.size> 0 # and list[0].size > 0 
#        report << "size #{list.size} '#{list[0].size}'"
        sep = list[0].size > 200 ? "\n\n" : "\n" if list #  sep long records with a blank line
        report << "\n    #{'+'* host.to_s.length}"
        report << "    #{host.to_s}"
        report << "    #{'+'* host.to_s.length}\n"
        report << list.join(sep) if  list
      }

    end

    def send_async(server, from, to, data)
    end

  end

end # of Action

##
# Hack in RSET

class Net::SMTP # :nodoc:

  unless instance_methods.include? 'reset' then
    ##
    # Resets the SMTP connection.

    def reset
      getok 'RSET'
    end
  end

end

class Mail < Net::SMTP

  def initialize(server, from, *args)
    @from = from
    @time = Time.now.to_i.to_s
    @count = 0
    super(server, 25)
    set_debug_output = $stderr
    if block_given? then
      begin
        return yeild(self.start(server, *args))
      ensure
        finish
      end
    else
      begin
	start(server, *args)
      rescue Timeout::Error
	retries += 1
	STDERR.puts "mail failed #{retries} for #{to}:#{$!}"
	sleep(10)
	reset
	retry if retries <= 2
      end
    end
  end

  def send (to, subject, data)
    retries = 0
    @count += 1
    to_array = to.split(/\s*,\s*/)

    hdrs = <<HDRS
To: #{to}
Subject: #{subject}
Date: #{Time.now.strftime("%a, %e %b %Y %T %z")}
Message-Id: <selms-#{@time}-#{@count}@selms>
From: #{@from}

HDRS

    send_message(hdrs + data.join("\n") + ".\n", @from, *to_array)
  rescue Net::SMTPFatalError, Net::SMTPSyntaxError, Timeout::Error
    if $! =~ /virtual alias table/ then
      retries += 1
      STDERR.puts "mail failed #{retries} for #{to}:#{$!}"
      sleep(10)
      reset
      retry if retries <= 2
    end
    STDERR.puts "mail failed for #{to}:#{$!}"
    reset
    false
  end
end
