require_relative '../environment'

require 'capybara/minitest'
require 'capybara/minitest/spec'
require 'rack_session_access/capybara'
require 'capybara/apparition'

Capybara.app = Sinatra::Application

include Capybara::Minitest::Assertions
Capybara.default_max_wait_time = 5

#Capybara.register_driver :apparition do |app|
#  Capybara::Apparition::Driver.new(app, headless: false)
#end

=begin
def setup
  Capybara.current_driver = :apparition
end

def teardown
  Capybara.reset_sessions!
  Capybara.use_default_driver
end
=end
=begin
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'rack_session_access/capybara'

Capybara.app = Sinatra::Application

def teardown
  Capybara.reset_sessions!
end
=end
