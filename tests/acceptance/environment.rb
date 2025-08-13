# frozen_string_literal: true
require_relative '../environment'

require 'capybara'
require 'capybara/minitest'
require 'capybara/minitest/spec'
require 'rack_session_access/capybara'

Capybara.app = Sinatra::Application
Capybara.default_max_wait_time = 5

Capybara.register_driver :selenium_chrome_headless_largewindow do |app|
  options = ::Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--window-size=1280,800') # Set your desired window size

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end