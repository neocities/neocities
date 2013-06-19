require 'selenium-webdriver'
require 'RMagick'

class ScreenshotJob
  include Backburner::Queue

  queue_priority 1000

  def self.perform(username)
    screenshot = Tempfile.new 'neocities_screenshot'
    screenshot.close

    caps = Selenium::WebDriver::Remote::Capabilities.htmlunit javascript_enabled: false, takesScreenshot: true

    driver = Selenium::WebDriver.for :remote, url: $config['phantomjs_url'], desired_capabilities: caps
    driver.manage.window.resize_to 1280, 720

    wait = Selenium::WebDriver::Wait.new(:timeout => 5) # seconds
    wait.until {
      driver.navigate.to "http://#{username}.neocities.org"
      driver.save_screenshot screenshot.path
    }

    driver.quit

    img_list = Magick::ImageList.new
    img_list.read screenshot.path
    screenshot.unlink
    img_list.new_image(img_list.first.columns, img_list.first.rows) { self.background_color = "white" }
    img = img_list.reverse.flatten_images
    puts 'boners'
    img.crop!(0, 0, 1280, 720)
    img.resize! 600, 400
    img.write File.join(DIR_ROOT, 'public', 'site_screenshots', "#{username}.jpg")
  end
end
