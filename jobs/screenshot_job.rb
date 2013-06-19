require 'selenium-webdriver'
require 'RMagick'

class ScreenshotJob
  include Backburner::Queue

  queue_priority 1000

  def self.perform(username)
    screenshot = Tempfile.new 'neocities_screenshot'
    screenshot.close

    driver = Selenium::WebDriver.for :remote, url: $config['phantomjs_url']
    driver.manage.window.resize_to 1280, 720

    wait = Selenium::WebDriver::Wait.new(:timeout => 5) # seconds
    wait.until {
      driver.navigate.to "http://#{username}.neocities.org"
      driver.save_screenshot screenshot.path
    }

    driver.quit

    img = Magick::Image.read(screenshot.path).first
    img.crop_resized!(600, 400, Magick::NorthGravity)
    img.write File.join(DIR_ROOT, 'public', 'site_screenshots', "#{user}.jpg")
  end
end
