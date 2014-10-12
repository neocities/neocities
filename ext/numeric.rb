class Numeric
  ONE_MEGABYTE = 1048576

  def roundup(nearest=10)
    self % nearest == 0 ? self : self + nearest - (self % nearest)
  end

  def to_mb
    self/ONE_MEGABYTE.to_f
  end

  def to_space_pretty
    space = (self.to_f / ONE_MEGABYTE).round(2)
    space = space.to_i if space.denominator == 1
    "#{space} MB"
  end
end