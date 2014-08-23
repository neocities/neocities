require_relative '../environment'

Capybara.app = Sinatra::Application

def teardown
  Capybara.reset_sessions!
end