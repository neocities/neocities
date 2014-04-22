require 'RMagick'

class ThumbnailWorker
  THUMBNAILS_PATH = File.join DIR_ROOT, 'public', 'site_thumbnails'
  include Sidekiq::Worker
  sidekiq_options queue: :thumbnails, retry: 3, backtrace: true

  def perform(username, filename)
    img_list = Magick::ImageList.new
    img_list.from_blob File.read(File.join(Site::SITE_FILES_ROOT, username, filename))
    img = img_list.first

    user_thumbnails_path = File.join THUMBNAILS_PATH, username
    FileUtils.mkdir_p user_thumbnails_path

    Site::THUMBNAIL_RESOLUTIONS.each do |res|
      resimg = img.resize_to_fit(*res.split('x').collect {|r| r.to_i})
      format = File.extname(filename).gsub('.', '')

      save_ext = format.match(Site::LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'

      resimg.write(File.join(user_thumbnails_path, "#{filename}.#{res}.#{save_ext}")) {
        self.quality = 90
      }
    end
  end
end