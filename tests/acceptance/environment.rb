require_relative '../environment'

Capybara.app = Sinatra::Application

def teardown
  Capybara.reset_sessions!
end

Capybara.default_wait_time = 5
