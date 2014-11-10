class Numeric
  ONE_MEGABYTE = 1000000

  def roundup(nearest=10)
    self % nearest == 0 ? self : self + nearest - (self % nearest)
  end

  def to_mb
    self/ONE_MEGABYTE.to_f
  end

  def to_bytes_pretty
    space = (self.to_f / ONE_MEGABYTE).round(2)
    space = space.to_i if space.denominator == 1
    if space >= 1000000
      "#{space/1000000} TB"
    elsif space >= 1000
      "#{space/1000} GB"
    else
      "#{space} MB"
    end
  end

  def format_large_number
    if self > 9999
      if self > 999999999
        unit_char = 'B' #billion
        unit_amount = 1000000000.0
      elsif self > 999999
        unit_char = 'M' #million
        unit_amount = 1000000.0
      elsif self > 9999
        unit_char = 'K' #thousand
        unit_amount = 1000.0
      end
    
      self_divided = self.to_f / unit_amount
      self_rounded = self_divided.round(1)

      if self_rounded.denominator == 1
        return sprintf ("%.0f" + unit_char), self_divided
      else
        return sprintf ("%.1f" + unit_char), self_divided
      end
    else
      if self > 999
        return self.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      else
        return self
      end
    end
  end

  def to_space_pretty
    to_bytes_pretty
  end
end