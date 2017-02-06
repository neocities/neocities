class Tempfile
  alias_method :size_original, :size
  def size
    s = size_original
    s.nil? ? 0 : s
  end
end
