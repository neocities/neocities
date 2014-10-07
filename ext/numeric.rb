class Numeric
  ONE_MEGABYTE = 1048576

  def roundup(nearest=10)
    self % nearest == 0 ? self : self + nearest - (self % nearest)
  end

  def to_mb
    self/ONE_MEGABYTE.to_f
  end

  def to_space_pretty
    "#{(self.to_f / ONE_MEGABYTE).round(2).to_s} MB"
  end
end