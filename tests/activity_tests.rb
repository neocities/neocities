# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe '/activity' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    SimpleCache.clear
  end

  after do
    SimpleCache.clear
  end

  it 'caches the unfiltered public record count' do
    get '/activity'

    _(last_response.status).must_equal 200
    _(SimpleCache.get(:activity_public_record_count)).wont_be_nil
  end

  it 'does not cache missing tag record counts' do
    3.times do |index|
      get "/activity?tag=tag#{index}"
      _(last_response.status).must_equal 200
    end

    _(SimpleCache.size).must_equal 0
  end

  it 'caches existing tag record counts by normalized tag' do
    Tag.create_unless_exists 'ActivityCacheTag'

    get '/activity?tag=%20ActivityCacheTag%20'

    _(last_response.status).must_equal 200
    _(SimpleCache.get(['activity_public_tag_record_count', 'activitycachetag'])).must_equal 0
    _(SimpleCache.get(['activity_public_tag_record_count', ' ActivityCacheTag '])).must_be_nil
  end
end
