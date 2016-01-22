require_relative '../environment'

require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'rack_session_access/capybara'

Capybara.app = Sinatra::Application

def teardown
  Capybara.reset_sessions!
end
