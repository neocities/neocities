require 'rmagick'
require 'timeout'
require 'securerandom'
require 'thread'
require 'open3'

class ScreenshotWorker
  SCREENSHOTS_PATH = Site::SCREENSHOTS_ROOT
  HARD_TIMEOUT = 30.freeze
  include Sidekiq::Worker
  sidekiq_options queue: :screenshots, retry: 3, backtrace: true

  def perform(username, path)
    path = "/#{path}" unless path[0] == '/'
    screenshot = Tempfile.new 'neocities_screenshot'
    screenshot.close
    screenshot_output_path = screenshot.path+'.png'

    line = Cocaine::CommandLine.new(
      "timeout #{HARD_TIMEOUT} phantomjs #{File.join DIR_ROOT, 'files', 'phantomjs_screenshot.js'}", ":url :output",
      expected_outcodes: [0]
    )

    begin
      output = line.run(
        url: "http://#{username}.neocities.org#{path}",
        output: screenshot_output_path
      )
    rescue Cocaine::ExitStatusError => e
      raise e

      # We set is_crashing after retries now, but use this code to go back to instant:

      #if e.message && e.message.match(/returned 124/)
      #  puts "#{username}/#{path} is timing out, discontinuing"
      #  site = Site[username: username]
      #  site.is_crashing = true
      #  site.save_changes validate: false
      #  return true
      #
      #else
      #  raise
      #end
    ensure
      screenshot.unlink
    end

    img_list = Magick::ImageList.new
    img_list.from_blob File.read(screenshot_output_path)

    screenshot.unlink
    File.unlink screenshot_output_path

    img_list.new_image(img_list.first.columns, img_list.first.rows) { self.background_color = "white" }
    img = img_list.reverse.flatten_images
    img_list.destroy!

    user_screenshots_path = File.join SCREENSHOTS_PATH, username
    screenshot_path = File.join user_screenshots_path, File.dirname(path)

    FileUtils.mkdir_p screenshot_path unless Dir.exists?(screenshot_path)

    Site::SCREENSHOT_RESOLUTIONS.each do |res|
      width, height = res.split('x').collect {|r| r.to_i}

      if width == height
        new_img = img.crop_resized width, height, Magick::NorthGravity
      else
        new_img = img.scale width, height
      end
      new_img.write(File.join(user_screenshots_path, "#{path}.#{res}.jpg")) {
        self.quality = 90
      }
      new_img.destroy!
    end

    img.destroy!

    GC.start full_mark: true, immediate_sweep: true

    true
  end

  sidekiq_retries_exhausted do |msg|
    username, path = msg['args']
    # This breaks too much so we're disabling it.
    #site = Site[username: username]
    #site.is_crashing = true
    #site.save_changes validate: false

=begin
        if site.email
          EmailWorker.perform_async({
            from: 'web@neocities.org',
            to: site.email,
            subject: "[NeoCities] The web page \"#{path}\" on your site (#{username}.neocities.org) is slow",
            body: "Hi there! This is an automated email to inform you that we're having issues loading your site to take a "+
                  "screenshot. It is possible that this is an error specific to our screenshot program, but it is much more "+
                  "likely that your site is too slow to be used with browsers. We don't want Neocities sites crashing browsers, "+
                  "so we're taking steps to inform you and see if you can resolve the issue. "+
                  "We may have to de-list your web site from being viewable in our browse page if it is not resolved shortly. "+
                  "We will review the site manually before taking this step, so don't worry if your site is fine and we made "+
                  "a mistake."+
                  "\n\nOur best,\n- Neocities"
          })
        end
=end
  end
end
