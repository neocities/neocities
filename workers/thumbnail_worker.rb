class ThumbnailWorker
  THUMBNAILS_PATH = Site::THUMBNAILS_ROOT
  MAXIMUM_IMAGE_SIZE = 10_000_000 # 10MB

  include Sidekiq::Worker
  sidekiq_options queue: :thumbnails, retry: 3, backtrace: true

  def perform(username, path)
    site = Site[username: username]
    return if site.nil?

    site_file_path = site.files_path(path)
    return unless File.exist?(site_file_path)

    # Large images can eat a ton of memory, so we skip for now.
    return if File.size(site_file_path) > MAXIMUM_IMAGE_SIZE

    user_thumbnails_path = site.base_thumbnails_path
    FileUtils.mkdir_p user_thumbnails_path
    FileUtils.mkdir_p File.join(user_thumbnails_path, File.dirname(path))

    Site::THUMBNAIL_RESOLUTIONS.each do |res|
      width, height = res.split('x').collect {|r| r.to_i}
      format = File.extname(path).gsub('.', '')
      full_thumbnail_path = File.join(user_thumbnails_path, "#{path}.#{res}.webp")

      begin
        image = Rszr::Image.load site_file_path
      rescue Rszr::LoadError
        next
      end

      begin
        if image.width > image.height
          image.resize! width, :auto
        else
          image.resize! :auto, height
        end
      rescue Rszr::TransformationError
        next
      end

      begin
        tmpfile = "/tmp/#{SecureRandom.uuid}.png"
        image.save(tmpfile)

        WebP.encode tmpfile, full_thumbnail_path, quality: 70
      ensure
        FileUtils.rm tmpfile
      end
    end
  end
end
