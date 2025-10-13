# frozen_string_literal: true
require_relative '../environment'

require 'capybara'
require 'capybara/minitest'
require 'capybara/minitest/spec'
require 'rack_session_access/capybara'

Capybara.app = Sinatra::Application
Capybara.default_max_wait_time = 10

Capybara.register_driver :selenium_chrome_headless_largewindow do |app|
  options = ::Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--window-size=1280,800') # Set your desired window size
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-features=VizDisplayCompositor') # Prevents DOM inspector issues
  options.add_argument('--host-resolver-rules=MAP * 127.0.0.1') # Block external requests
  options.add_argument('--disable-background-networking') # Prevent background network activity

  client = Selenium::WebDriver::Remote::Http::Default.new
  client.read_timeout = 120
  client.open_timeout = 120

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, http_client: client)
end

# Work around Chrome intermittently reporting stale DOM nodes as UnknownError.
module Neocities
  module CapybaraStaleNodePatch
    STALE_NODE_MESSAGE = 'Node with given id does not belong to the document'

    def visible?(*args, &block)
      with_stale_node_retry { super(*args, &block) }
    end

    def visible_text(*args, &block)
      with_stale_node_retry { super(*args, &block) }
    end

    private

    def with_stale_node_retry
      yield
    rescue Selenium::WebDriver::Error::UnknownError => e
      raise unless e.message&.include?(STALE_NODE_MESSAGE)

      raise Selenium::WebDriver::Error::StaleElementReferenceError, e.message
    end
  end
end

Capybara::Selenium::Node.prepend(Neocities::CapybaraStaleNodePatch)
