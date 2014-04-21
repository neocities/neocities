require 'RMagick'

class ScreenshotWorker
  REQUIRED_RESOLUTIONS = ['235x141', '105x63', '270x162']
  SCREENSHOTS_PATH = File.join DIR_ROOT, 'public', 'site_screenshots'
  include Sidekiq::Worker
  sidekiq_options queue: :screenshots, retry: 3, backtrace: true

  def perform(username, filename)
    screenshot = Tempfile.new 'neocities_screenshot'
    screenshot.close
    screenshot_output_path = screenshot.path+'.png'

    f = Screencap::Fetcher.new("http://#{username}.neocities.org/#{filename}")
    f.fetch(
      output: screenshot_output_path,
      width: 1280,
      height: 720
    )


    img_list = Magick::ImageList.new
    img_list.from_blob File.read(screenshot_output_path)

    screenshot.unlink
    File.unlink screenshot_output_path

    img_list.new_image(img_list.first.columns, img_list.first.rows) { self.background_color = "white" }
    img = img_list.reverse.flatten_images

    user_screenshots_path = File.join SCREENSHOTS_PATH, username
    FileUtils.mkdir_p user_screenshots_path

    REQUIRED_RESOLUTIONS.each do |res|
      img.scale(*res.split('x').collect {|r| r.to_i}).write(File.join(user_screenshots_path, "#{filename}.#{res}.jpg")) {
        self.quality = 90
      }
    end
  end
end