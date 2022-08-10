require 'rmagick'

class ThumbnailWorker
  THUMBNAILS_PATH = Site::THUMBNAILS_ROOT
  MAXIMUM_IMAGE_SIZE = 2_000_000 # 2MB

  include Sidekiq::Worker
  sidekiq_options queue: :thumbnails, retry: 3, backtrace: true

  def perform(username, path)
    site = Site[username: username]
    return if site.nil?

    site_file_path = site.files_path(path)
    return unless File.exist?(site_file_path)

    # Large images jam up ImageMagick and eat a ton of memory, so we skip for now.
    return if File.size(site_file_path) > MAXIMUM_IMAGE_SIZE

    img_list = Magick::ImageList.new

    begin
      img_list.from_blob File.read(site_file_path)
    rescue Errno::ENOENT => e # Not found, skip
      return
    rescue Magick::ImageMagickError => e
      GC.start full_mark: true, immediate_sweep: true
      puts "thumbnail fail: #{site_file_path} #{e.inspect}"
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

      resimg.write(full_thumbnail_path) { |i|
        i.quality = 75
      }
      resimg.destroy!
      #$image_optim.optimize_image! full_thumbnail_path
    end

    img.destroy!
    GC.start full_mark: true, immediate_sweep: true
  end
end
