
module Ago
  module VERSION
    MAJOR = 0
    MINOR = 1
    TINY = 5

    class << self
      def pretty
        "#{MAJOR}.#{MINOR}.#{TINY}"
      end
      alias_method :print, :pretty
    end
  end

  Ago::Order = [:year, :month, :week, :day, :hour, :minute, :second]
  Ago::Units = {
    :year => {
      :basic => 60 * 60 * 24 * 365,
      :gregorian => 86400 * 365.2425,
      },
    :month => {
      :basic => 60 * 60 * 24 * 30,
      :gregorian => 86400 * 30.436875,
      },
    :week => {
      :basic => 60 * 60 * 24 * 7,
      :gregorian => 86400 * 7.02389423076923,
      },
    :day => {
      :basic => 60 * 60 * 24
      },
    :hour => {
      :basic => 60 * 60
      },
    :minute => {
      :basic => 60
      },
    :second => {
      :basic => 1
      }
    }

  def Ago.calendar_check(calendar)
    error = ":calendar => value must be either :basic or :gregorian."
    unless calendar == :basic || calendar == :gregorian
      raise ArgumentError, error
    end
  end


  module Ago::TimeAgo
    # Generate List of valid unit :symbols
    valids = ""
    Ago::Order.each do |u|
      unless u == :second
        valids += ":#{u.to_s}, "
      else
        valids += "and :#{u.to_s}."
      end
    end
    Valids = valids

    def ago_in_words(opts={})
      # Process options {hash}
      focus = opts[:focus] ? opts[:focus] : 0
      start_at = opts[:start_at] ? opts[:start_at] : :year
      now = opts[:now] ? opts[:now] : Time.now
      in_time = opts[:in_time] ? opts[:in_time] : :past
      calendar = opts[:calendar] ? opts[:calendar] : :basic

      # Filter out invalid arguments for :in_time
      in_time_error = ":in_time => value must be either :past or :future, " \
                     + "depending on whether the Time object is before or after Time.now."
      unless in_time == :past || in_time == :future
        raise ArgumentError, in_time_error
      end

      # Filter out invalid arguments for :calendar
      Ago.calendar_check(calendar)

      # Filter out invalid arguments for :start_at and :focus
      base_error = " => value must either be a number " +
        "between 0 and 6 (inclusive),\nor one of the following " +
        "symbols: " + Valids
      {:focus => focus, :start_at => start_at}.each do |key, opt|
        opt_error = ":" + key.to_s + base_error
        if opt.class == Integer
          raise ArgumentError, opt_error unless opt >= 0 && opt <= 6
        elsif opt.class == Symbol
          raise ArgumentError, opt_error unless Ago::Units[opt]
        else
          raise ArgumentError, opt_error
        end
      end

      # Create Variables necessary for processing.
      frags = []
      output = ""
      count = 0

      now = calendar == :basic ? now.to_i : now.to_f
      my_time = calendar == :basic ? self.to_i : self.to_f
      if now > my_time
        diff = now - my_time
        tail = " ago"
      elsif my_time > now
        diff = my_time - now
        tail = " from now"
      else
        diff = 0
        tail = "just now"
      end

      # Begin Ago.ago processing
      Ago::Order.each do |u|
        if calendar == :gregorian && Ago::Units[u][:gregorian]
          value = Ago::Units[u][:gregorian]
        else
          value = Ago::Units[u][:basic]
        end
        count += 1

        # Move further ahead in the Ago::Units array if start_at is farther back than
        # the current point in the array.
        if start_at.class == Integer
          next if count <= start_at
        elsif start_at.class == Symbol
          next if Ago::Order.index(u) < Ago::Order.index(start_at)
        end

        n = (diff/value).floor
        if n > 0
          plural = n > 1 ? "s" : ""
          frags << "#{n} #{u.to_s + plural}"

          # If the argument passed into ago() is a symbol, focus the ago statement
          # down to the level specified in the symbol
          if focus.class == Symbol
            break if u == focus || u == :second
          elsif focus.class == Fixnum
            if focus == 0 || u == :second
              break
            else
              focus -= 1
            end
          end
          diff -= n * value
        end
      end

      # Der Kommissar
      frags.size.times do |n|
        output += frags[n]
        output += ", " unless n == frags.size - 1
      end

      return output + "#{tail}"
    end

    def from_now_in_words(opts={})
      ago_in_words(opts)
    end
  end
end

class Time
  include Ago::TimeAgo
end
