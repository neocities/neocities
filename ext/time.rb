class Time
  alias_method :ago_original, :ago

  def ago
   ago_original.downcase.gsub('right now, this very moment.', 'just now')
  end
end