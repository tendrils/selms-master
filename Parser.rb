
module Parser

  OPTIONAL = true
  SAME_LINE = 1
  ANYWHERE  = 2

  @@singleQstring = /^'([^']*)'/
  @@doubleQstring = /^"([^"]*)"/

  @@TimeUnits = { 
    'sec'    => 1,
    'second' => 1,
    'minute' => 60,
    'min'    => 60,
    'hour'   => 3600,
    'day'    => 3600 * 24
  }

# define accessor methods to get at module state

  def line() @@line end
  def lineno() @@f.lineno end
  def originalLine() @@originalLine end
  def token() @@token end
  def debug=(debug) @@debug=debug end
  def errors() @@errors end

  def setup( filename )
    @@f = File.new(filename ) 
    return nil unless @@f
    @@file_name = filename
    @@line = ''
    @@errors = 0
    @@debug = false
    @@macros = {}
    @@included_from = []
  end

  def read_next_line
    begin
      @@line = (@@f.gets)
      if ! @@line && @@included_from.size > 0 then  # in included file 
	@@f, @@file_name, @@macros = @@included_from.pop
	read_next_line
      end
      return nil unless @@line
      @@line.chomp!
      @@line.lstrip!
    end while @@line == '' or @@line =~ /^#/   # skip blank and comment lines

    while @@line =~ /\\$/  # line ends in a '\' -- next line is a cont
      line.chop!
      @@line += ' ' + (@@f.gets).chomp!
      @@line.lstrip!
    end

    if @@line =~ /^include (\S+)/ then  # open included file
      include = $1
      if include =~ /^\+/ then   # relative file name
	if ENV['SELMS_ETC'] then 
	  loc = ENV['SELMS_ETC']+'/'
	else 
	  @@file_name =~ %r!(.+/)[^/]+$!
	  loc = $1 if $`
	end
	include.sub!(/^\+/, "#{loc}" ) if loc
      end
      @@included_from << [@@f.dup, @@file_name.dup, @@macros.dup ]
      @@f = File.new(include ) 
      if @@f then
	@@file_name = include
	read_next_line
      else
	@@f, @@file_name = @@included_from.pop
	error("failed to open include file '#{$0}'")
	read_next_line
      end
    end

# macro definition

    if @@line =~ /^(\$[A-Z_]+)\s*=\s*(.+)/ then
      @@macros[$1] = $2
      read_next_line
    end

# macro substution
    while @@line =~ /(?!`)(\$[A-Z_]+)/ do
      macro = $1
      if val =  macro_value(macro) then
	macro = '\\' + macro
	@@line.sub!(/#{macro}/, val )
      else
	error("undefined macro #{macro}")
	break
      end
    end
    @@originalLine = @@line.dup

  end

  def macro_value( key )
    return @@macros[key] if @@macros[key] ;
    @@included_from.reverse_each { |file, name, macros|
      return macros[key] if macros[key] ;
    }
    return nil
  end


  def skip_whitespace ( where=ANYWHERE )
    @@line.lstrip!
    if ( @@line == '' || @@line =~ /^#/ ) and where == SAME_LINE then
      return nil
    end

    return @@line unless @@line == '' or @@line =~ /^#/
    
    return read_next_line
   
  end


# returns number of second in the given interval

  def timeInterval( optional=nil ) 

    if num = expect(/(\d+)/, "integer", ANYWHERE, optional ) then
      n = num.to_i
      if mult = expect( @@TimeUnits, "Time Units", SAME_LINE, true )then
        num.to_i * mult
      else
        nil 
      end
    else
      nil 
    end
  end  

# expect takes an RE, a string or a hash of keywords and extracts
# an appropriate token from the stat of the current buffer.
# if it does not find any suitable token is prints an error unless 
# optional is passed 

  def expect ( what, descr=nil, where=ANYWHERE, optional=false )
    @@token = nil
    return nil unless skip_whitespace( where )

    what = what.to_s if what.class.to_s == 'Class'

    # expecting an RE terminated by a <tab> ?
    if what == 're'  then
      if look_ahead( '/' ) then  # its a real re
	@@line.sub!( %r'^/(.+)/\s*(?:\t|$)', '')
      elsif t = look_ahead( /^%r(.)/ ) then
	@@line.sub!( %r<^%r#{t}(.+)#{t}\s*(?:\t|$)>, '')
      end
      if re = $1 then
	begin 
	  @re = Regexp.new( re )
	  re = t ? "%r#{t}#{re}#{t}" : "/#{re}/"
	rescue RegexpError
	  error("RE error: " + $!)
	  @errors = true
	  rest_of_line
	  return nil
	end
	return re || true
      else
	error("Expecting a regular expression followed by a *tab*") if ! optional
	return nil
      end
    elsif what == 'String' then
      if ! quoted_string( SAME_LINE, Optional)  then
	expect( /^([^ \t\]}&|]+)/)
      end
    elsif what == 'Integer' then
	@@token = @@token.to_i if expect( /^(\d+)/)
    end

    case (what.class).to_s
    when 'String'   then
      if @@line.index(what) == 0 then
        @@line.slice!(0, what.length)
        @@token = what
      end
    when 'Regexp'  then
      @@token = ((defined? $1) ? $1 : true) if @@line.sub!(what, '')
    when 'Proc'
      r = what.call
    when 'Array'
      if @@line =~ /^(\w+)/
        what.each { |t|
          if t == $1
          ret = @@token = t
          @@line.sub!(/^(\w+)/,'')
          break
        end
        }
      end
    when 'Hash'
      if @@line =~ /^(\w+)/
        if defined? what[$1] then
          @@token = $1
          ret = what[$1]
          @@line.sub!(/^(\w+)/,'')
        end
      end
    else
      error("Parser does not know what to do with '#{what.class.to_s}' in Parser::expect") 
    end
     
    STDOUT.puts "Expect: #{@@token}" if @@debug
    return ret if  ret
    return @@token if @@token

    descr ||= what

    # have fallen though -- must not have found what we were looking for
    error( "Expecting #{descr}" ) unless optional
    
  end

#
#  nextT returns the next token - a special character
#                              - alphanumeric token (starts with alpha)
#                              - integer
#
  def nextT ( where=ANYWHERE )

    @@token = nil

    return nil unless skip_whitespace( where )

    @@save_line = @@line.dup

    case @@line[0]
    when ?!..?/, ?:..?@, ?[..?`, ?{..?~         # special
      @@token = @@line.slice!(0,1)
    when ?a..?z, ?A..?Z          # alpha
      @@line.sub!( /(\w+)/, '')
      @@token = $1
    when ?0..?9
      @@line.sub!( /(\d+)/, '')
      @@token = $1
    else
      error("unxepected character '#{@@line.slice!(0,1)}'")
      nil
    end
    STDOUT.puts "Next: #{@@token}" if @@debug
    @@token
  end

# undo the effect of the last nextT

  def back_up
    @@line = @@save_line
  end

# look_ahead returns true if the given RE matches the next thing to be 
# parsed

  def look_ahead( what, where=ANYWHERE ) 

    return nil unless skip_whitespace( where )

    case what.class.to_s
    when 'Regexp'
      if @@line =~ what then
	return $1 ? $1 : true
      end
    when 'String'
      return @@line[0,what.length] == what
    else
      error( "error in parser, don't know what to do with object of class #{what.class}");
    end
    return nil
  end

  # gets a quoted string delimited by either single or double quotes
  # currently does not handle escaped delimiters within the string
  # Note: default value for where is different to most other methods

  def quoted_string( where = SAME_LINE, optional = false ) 
    
    return nil unless skip_whitespace( where )

    re = case @@line[0]
    when ?' : @@singleQstring
    when ?" : @@doubleQstring
    else 
      return nil if optional
      error("Expecting a <quoted string>")
    end

    expect( re, "<closing quote>", where, false ) 
  end

# rest_of_line returns the rest of the current line as a string

  def rest_of_line

    return nil unless skip_whitespace( SAME_LINE )

    l = @@line.dup
    @@line = ''
    return l
  end

# parse a list of items separated by commas, each item must either be 
# delimited by quotes or not contain white space. There is no mechanism 
# for quoting string delimeters within the string.

  def getList

    list = []
    begin  
      list.push( quotedString( ANYWHERE ) )
    end while nextT == ','  # next is a reseved word!!!

    return list
    end

# prints the current line number and the line then the error message and\
# the current token

  def error( message, lineno=nil, error = true)

    @@errors += 1 if error

    @@included_from.each { |incl|
      STDERR.puts "#{incl[1]}:#{incl[0].lineno}:"
    }
      

    where = lineno 
    if lineno then
      STDERR.puts "Section starting at #{@@file_name}:#{lineno}:",
                  " #{message}"
    else
      STDERR.puts "#{@@file_name}:#{@@f.lineno}:#{@@originalLine}",
                  "    #{message} near '#{@@token} #{@@line}'"
    end
    return nil
  end

  def warn( message, lineno=nil )
    error( message, lineno, false )
  end

  # resetError returns the current error counter and resets it to zero

  def reset_errors
    e = @@errors
    @@errors = 0
    return e
  end

  # recover is called after detection of a syntax error to try and find
  # a know place to start again. If sameLine is true then only look on 
  # current line. What is a string or RegExpr to search for.
  #
  # Returns what it found or nil
  #
  def recover ( what, sameLine=Parser::ANYWHERE, descr=nil )
    while ! (i = @@line.index(what) )
      return nil if defined? sameLine
      @@line = (@@f.gets).chomp!
    end
    @@line.slice!(0, i-1) unless i == 0;   # remove any text before the match
    return what if what.class.to_s == 'String'
    return $&   # the part that was matched by the RE

    rescue EOFEorror
      @@eof = TRUE
      error("Unexpected EOF while looking for #{descr}") unless @@included_from.size > 0
      return nil
  end
end  # class Parser


