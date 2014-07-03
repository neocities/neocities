class String
  def empty?
    strip == '' ? true : false
  end

  def shorten(length, usedots=true)
    if usedots
      return self if self.length < length
      "#{self[0..length-3]}..."
    else
      self[0..length]
    end
  end
end
