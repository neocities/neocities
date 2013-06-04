class SiteFile
  attr_reader :filename, :ext

  def initialize(filename)
    @filename = filename
    @ext = File.extname(@filename).sub(/^./, '')
  end
end