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
    gsub /^#{scan(/^\s*/).min_by{|l|l.length}}/, ""
  end
end
