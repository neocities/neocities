# frozen_string_literal: true
require_relative './environment.rb'

describe '/search' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    Capybara.default_driver = :rack_test
    Capybara.reset_sessions!
  end

  it 'redirects post search submissions to the get search page' do
    post '/search', q: 'weird web'

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_equal 'http://example.org/search?q=weird+web'
  end
end
