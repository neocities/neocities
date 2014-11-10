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

  def format_large_numbers
    if self > 999999999
      return sprintf "%.2fB", (self/1000000000.0)
    elsif self > 999999
      return sprintf "%.2fM", (self/1000000.0)
    elsif self > 999
      return sprintf "%.2fK", (self/1000.0)
    else
      return self
    end
  end

  def to_space_pretty
    to_bytes_pretty
  end
end