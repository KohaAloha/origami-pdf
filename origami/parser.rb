=begin

= File
	parser.rb

= Info
	Origami is free software: you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Origami is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with Origami.  If not, see <http://www.gnu.org/licenses/>.

=end

require 'strscan'

module Origami
  
  if RUBY_PLATFORM =~ /win32/ 
    require "Win32API"
  
    getStdHandle = Win32API.new("kernel32", "GetStdHandle", ['L'], 'L')
    @@setConsoleTextAttribute = Win32API.new("kernel32", "SetConsoleTextAttribute", ['L', 'N'], 'I')

    @@hOut = getStdHandle.call(-11)
  end

  module Colors #:nodoc;
    if RUBY_PLATFORM =~ /win32/
      BLACK     = 0
      BLUE      = 1
      GREEN     = 2
      CYAN      = 3
      RED       = 4
      MAGENTA   = 5
      YELLOW    = 6
      GREY      = 7
      WHITE     = 8
    else
      GREY      = '0;0'
      BLACK     = '0;30'
      RED       = '0;31'
      GREEN     = '0;32'
      YELLOW    = '0;33'
      BLUE      = '0;34'
      MAGENTA   = '0;35'
      CYAN      = '0;36'
      WHITE     = '0;37'
      BRIGHT_GREY       = '1;30'
      BRIGHT_RED        = '1;31'
      BRIGHT_GREEN      = '1;32'
      BRIGHT_YELLOW     = '1;33'
      BRIGHT_BLUE       = '1;34'
      BRIGHT_MAGENTA    = '1;35'
      BRIGHT_CYAN       = '1;36'
      BRIGHT_WHITE      = '1;37'
    end
  end

  def set_fg_color(color, bright = false, fd = STDOUT) #:nodoc:
    if RUBY_PLATFORM =~ /win32/
      if bright then color |= Colors::WHITE end
      @@setConsoleTextAttribute.call(@@hOut, color)
      yield
      @@setConsoleTextAttribute.call(@@hOut, Colors::GREY)
    else
      col, nocol = [color, Colors::GREY].map! { |key| "\033[#{key}m" }
      fd << col
      yield
      fd << nocol
    end
  end

  unless RUBY_PLATFORM =~ /win32/
    def colorize(text, color, bright = false)
      col, nocol = [color, Colors::GREY].map! { |key| "\033[#{key}m" }
      "#{col}#{text}#{nocol}"
    end
  end

  def colorprint(text, color, bright = false, fd = STDOUT) #:nodoc:
    set_fg_color(color, bright, fd) {
      fd << text
    }    
  end

	EOL = "\r\n" #:nodoc:
  DEFINED_TOKENS = "[<\\[(%\\/)\\]>]" #:nodoc:
  WHITESPACES = "([ \\f\\t\\r\\n\\0]|%[^\\n]*\\n)*" #:nodoc:
  WHITECHARS = "[ \\f\\t\\r\\n\\0]*" #:nodoc:
  WHITECHARS_NORET = "[ \\f\\t\\0]*" #:nodoc:
  
  REGEXP_WHITESPACES = Regexp.new(WHITESPACES) #:nodoc:

  class Parser #:nodoc:

    class ParsingError < Exception #:nodoc:
    end
   
    #
    # Do not output debug information.
    #
    VERBOSE_QUIET = 0
    
    #
    # Output some useful information.
    #
    VERBOSE_INFO = 1
    
    #
    # Output debug information.
    #
    VERBOSE_DEBUG = 2
    
    #
    # Output every objects read
    # 
    VERBOSE_INSANE = 3
    
    attr_accessor :options
    
    def initialize(options = {}) #:nodoc:
      
      #Default options values
      @options = 
      { 
        :verbosity => VERBOSE_INFO, # Verbose level.
        :ignore_errors => true,    # Try to keep on parsing when errors occur.
        :callback => Proc.new {},   # Callback procedure whenever a structure is read.
        :prompt_password => Proc.new { print "Password: "; gets.chomp }, #Callback procedure to prompt password when document is encrypted.
        :force => false # Force PDF header detection
      }
     
      @options.update(options)
    end

    def parse(stream)
      data = 
      if stream.respond_to? :read
        StringScanner.new(stream.read)
      elsif stream.is_a? ::String
        StringScanner.new(File.open(stream, "r").binmode.read)
      elsif stream.is_a? StringScanner
        stream
      else
        raise TypeError
      end
    
      @data = data
      @data.pos = 0
    end
    
    def parse_objects(file) #:nodoc:
      begin
        loop do 
          obj = Object.parse(@data)
          return if obj.nil?

          trace "Read #{obj.type} object#{if obj.type != obj.real_type then " (" + obj.real_type.to_s.split('::').last + ")" end}, #{obj.reference}"
          
          file << obj
                    
          @options[:callback].call(obj)
        end
        
      rescue UnterminatedObjectError => e
        error e.message
        file << e.obj

        @options[:callback].call(e.obj)

        Object.skip_until_next_obj(@data)
        retry

      rescue Exception => e
        error "Breaking on: #{(@data.peek(10) + "...").inspect} at offset 0x#{@data.pos.to_s(16)}"
        error "Last exception: [#{e.class}] #{e.message}"
        debug "-> Stopped reading body : #{file.revisions.last.body.size} indirect objects have been parsed" if file.is_a?(PDF)
        abort("Manually fix the file or set :ignore_errors parameter.") if not @options[:ignore_errors]

        debug 'Skipping this indirect object.'
        raise(e) if not Object.skip_until_next_obj(@data)
            
        retry
      end
    end
    
    def parse_xreftable(file) #:nodoc:
      begin
        info "...Parsing xref table..."
        file.revisions.last.xreftable = XRef::Section.parse(@data)
        @options[:callback].call(file.revisions.last.xreftable)
      rescue Exception => e
        debug "Exception caught while parsing xref table : " + e.message
        warn "Unable to parse xref table! Xrefs might be stored into an XRef stream."

        @data.pos -= 'trailer'.length unless @data.skip_until(/trailer/).nil?
      end
    end
    
    def parse_trailer(file) #:nodoc:
      begin
        info "...Parsing trailer..."
        trailer = Trailer.parse(@data)

        if file.is_a?(PDF)
          xrefstm = file.get_object_by_offset(trailer.startxref) || 
          (file.get_object_by_offset(trailer.XRefStm) if trailer.has_field? :XRefStm)
        end

        if not xrefstm.nil?
          debug "Found a XRefStream for this revision at #{xrefstm.reference}"
          file.revisions.last.xrefstm = xrefstm
        end

        file.revisions.last.trailer = trailer
        @options[:callback].call(file.revisions.last.trailer)
       
      rescue Exception => e
        debug "Exception caught while parsing trailer : " + e.message
        warn "Unable to parse trailer!"
            
        abort("Manually fix the file or set :ignore_errors parameter.") if not @options[:ignore_errors]

        raise
      end
    end

    private
 
    def error(str = "") #:nodoc:
      colorprint("[error] #{str}\n", Colors::RED, false, STDERR)
    end

    def warn(str = "") #:nodoc:
      colorprint("[info ] Warning: #{str}\n", Colors::YELLOW, false, STDERR) if @options[:verbosity] >= VERBOSE_INFO
    end

    def info(str = "") #:nodoc:
      (colorprint("[info ] ", Colors::GREEN, false, STDERR); STDERR << "#{str}\n") if @options[:verbosity] >= VERBOSE_INFO
    end
    
    def debug(str = "") #:nodoc:
      (colorprint("[debug] ", Colors::MAGENTA, false, STDERR); STDERR << "#{str}\n") if @options[:verbosity] >= VERBOSE_DEBUG
    end
    
    def trace(str = "") #:nodoc:
      (colorprint("[trace] ", Colors::CYAN, false, STDERR); STDERR << "#{str}\n") if @options[:verbosity] >= VERBOSE_INSANE
    end
  end
end

