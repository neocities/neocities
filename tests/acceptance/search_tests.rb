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
    $redis_cache.del('search_query_count')
  end

  it 'shows a playful standalone search page' do
    visit '/search'

    _(page).must_have_selector 'img.search-mascot[src="/img/hotcat.svg"][alt="Hot Cat"]'
    _(page).must_have_content 'Search the handmade web'
    _(page).must_have_selector 'form[action="/search"] input[name="q"]'
    _(page).must_have_link 'Random Site', href: '/browse?sort_by=random'
  end

  it 'links to search immediately after websites in the top nav' do
    visit '/search'

    nav_links = all('.constant-Nav a').map(&:text)
    _(nav_links[nav_links.index('Websites') + 1]).must_equal 'Search'
  end

  it 'does not mount the old browse search path' do
    visit '/browse/search'

    _(page.status_code).must_equal 404
  end

  it 'redirects post search submissions to the get search page' do
    post '/search', q: 'weird web'

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_equal 'http://example.org/search?q=weird+web'
  end

  it 'shows the mascot on the results header' do
    $redis_cache.set('search_query_count', $config['google_custom_search_query_limit'], ex: 86400)

    visit '/search?q=web'

    _(page).must_have_selector '.header-Outro img.search-results-mascot[src="/img/hotcat.svg"][alt="Hot Cat"]'
    _(page).wont_have_selector '.header-Outro h1', text: 'Site Search'
  end
end
