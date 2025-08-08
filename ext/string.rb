class String
  def shorten(length, usedots=true)
    if usedots
      return self if self.length < length
      "#{self[0..length-3]}..."
    else
      self[0..length]
    end
  end

  def unindent
    gsub /^#{Regexp.quote(scan(/^\s*/).min_by{|l|l.length})}/, ""
  end

  def blank?
    return true if self == ''
    false
  end

  def not_an_integer?
    Integer(self)
    false
  rescue ArgumentError
    true
  end
end
