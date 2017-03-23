require 'rmagick'

class ThumbnailWorker
  THUMBNAILS_PATH = Site::THUMBNAILS_ROOT
  include Sidekiq::Worker
  sidekiq_options queue: :thumbnails, retry: 3, backtrace: true

  def perform(username, path)
    site = Site[username: username]

    img_list = Magick::ImageList.new

    begin
      img_list.from_blob File.read(site.files_path(path))
    rescue Errno::ENOENT => e # Not found, skip
      return
    end

    img = img_list.first

    user_thumbnails_path = site.base_thumbnails_path
    FileUtils.mkdir_p user_thumbnails_path
    FileUtils.mkdir_p File.join(user_thumbnails_path, File.dirname(path))

    Site::THUMBNAIL_RESOLUTIONS.each do |res|
      resimg = img.resize_to_fit(*res.split('x').collect {|r| r.to_i})
      format = File.extname(path).gsub('.', '')

      save_ext = format.match(Site::LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'

      full_thumbnail_path = File.join(user_thumbnails_path, "#{path}.#{res}.#{save_ext}")

      resimg.write(full_thumbnail_path) {
        self.quality = 75
      }
      #$image_optim.optimize_image! full_thumbnail_path
    end
  end
end
