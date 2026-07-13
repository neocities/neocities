# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe 'tutorial' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session_env(token='abcd', session_extra={})
    {'rack.session' => {'id' => @site.id, '_csrf_token' => token}.merge(session_extra)}
  end

  def walked_to(section, page)
    {'tutorial_walk' => {section => page}}
  end

  before do
    @site = Fabricate :site, tutorial_required: true
  end

  it 'lifts the tutorial requirement when a site becomes a supporter' do
    @site.plan_type = 'supporter'
    @site.save_changes validate: false

    _(@site.reload.tutorial_required).must_equal false

    get '/dashboard', {}, session_env
    _(last_response.status).must_equal 200

    cancelled = Fabricate :site, tutorial_required: true
    cancelled.plan_type = nil
    cancelled.save_changes validate: false

    _(cancelled.reload.tutorial_required).must_equal true
  end

  it 'redirects tutorial-required sites to the tutorial welcome page' do
    get '/dashboard', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial\z}
  end

  it 'welcomes required sites with an intro instead of the chooser' do
    get '/tutorial', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Welcome to Neocities!'
    _(last_response.body).must_include 'Start the tutorial'
    _(last_response.body).must_include '/tutorial/html/1'
    _(last_response.body).wont_include 'Go to the dashboard'
  end

  it 'offers required sites mid-walk a continue link' do
    get '/tutorial', {}, session_env('abcd', walked_to('html', 4))

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Continue the tutorial'
    _(last_response.body).must_include '/tutorial/html/4'
  end

  it 'redirects sites that are not tutorial required to the learn page' do
    @site.update tutorial_required: false

    get '/tutorial', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorials\z}
  end

  it 'requires login' do
    get '/tutorial/html/1'

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/\z}
  end

  it 'redirects each section index to its first page' do
    @site.update tutorial_required: false

    TUTORIAL_SECTIONS.each do |section|
      get "/tutorial/#{section}", {}, session_env

      _(last_response.status).must_equal 302
      _(last_response.headers['Location']).must_match %r{/tutorial/#{section}/1\z}
    end
  end

  it 'not founds unknown sections and out of range pages' do
    @site.update tutorial_required: false

    ['/tutorial/php/1', '/tutorial/html/0', "/tutorial/html/#{TUTORIAL_PAGE_COUNT + 1}", '/tutorial/html/banana', '/tutorial/html/01', '/tutorial/css/0'].each do |path|
      get path, {}, session_env
      _(last_response.status).must_equal 404, "expected 404 for #{path}"
    end
  end

  it 'does not advance the walk on a post without csrf' do
    post '/tutorial/html/8', {}, session_env('abcd', walked_to('html', 8))

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/\z}
    _(@site.reload.tutorial_required).must_equal true
  end

  it 'advances the walk with a csrf-carrying post, one page at a time' do
    post '/tutorial/html/1', {csrf_token: 'abcd'}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/2\z}

    get '/tutorial/html/2', {}, session_env

    _(last_response.status).must_equal 200, 'the walk should have advanced to page 2'
    _(@site.reload.tutorial_required).must_equal true

    clear_cookies
    post '/tutorial/html/5', {csrf_token: 'abcd'}, session_env

    _(last_response.status).must_equal 302, 'posting ahead of the walk should not advance it'
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}
  end

  it 'completes the required tutorial when the walk reaches the review step' do
    post '/tutorial/html/8', {csrf_token: 'abcd'}, session_env('abcd', walked_to('html', 8))

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/9\z}
    _(@site.reload.tutorial_required).must_equal true, 'completion happens on viewing the review page, not the post'

    get '/tutorial/html/9', {}, session_env('abcd', walked_to('html', 9))

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Review And Save'
    _(@site.reload.tutorial_required).must_equal false
  end

  it 'completes the required tutorial from any section review step' do
    get '/tutorial/css/9', {}, session_env('abcd', walked_to('css', 9))

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Review Your Page'
    _(@site.reload.tutorial_required).must_equal false
  end

  it 'sends required sites jumping ahead back to their current page' do
    get '/tutorial/html/5', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}
    _(@site.reload.tutorial_required).must_equal true

    get '/tutorial/html/9', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}
    _(@site.reload.tutorial_required).must_equal true

    get '/tutorial/html/7', {}, session_env('abcd', walked_to('html', 4))

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/4\z}
  end

  it 'lets required sites revisit earlier pages of the walk' do
    get '/tutorial/html/3', {}, session_env('abcd', walked_to('html', 6))

    _(last_response.status).must_equal 200
    _(@site.reload.tutorial_required).must_equal true
  end

  it 'renders the advance form for required sites without a token in any url' do
    get '/tutorial/html/1', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'id="advanceForm"'
    _(last_response.body).must_include 'action="/tutorial/html/1"'
    _(last_response.body).wont_include '?csrf_token='
  end

  it 'walks non-required sites through the pages in order too' do
    @site.update tutorial_required: false

    get '/tutorial/html/5', {}, session_env

    _(last_response.status).must_equal 302, 'jumping ahead should bounce for everyone'
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}

    post '/tutorial/html/1', {csrf_token: 'abcd'}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/2\z}

    get '/tutorial/html/2', {}, session_env

    _(last_response.status).must_equal 200, 'the walk should carry non-required sites forward'
  end

  it 'unlocks the finale once the walk reaches the review page' do
    @site.update tutorial_required: false

    get '/tutorial/html/10', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}

    get '/tutorial/html/10', {}, session_env('abcd', walked_to('html', TUTORIAL_COMPLETION_PAGE))

    _(last_response.status).must_equal 200
  end

  it 'does not complete the tutorial on earlier pages' do
    TUTORIAL_SECTIONS.each do |section|
      1.upto(TUTORIAL_COMPLETION_PAGE - 1) do |page|
        get "/tutorial/#{section}/#{page}", {}, session_env('abcd', walked_to(section, page))
        _(last_response.status).must_equal 200
        _(@site.reload.tutorial_required).must_equal true, "#{section} page #{page} should not complete the tutorial"
      end
    end
  end

  it 'renders every tutorial page of every section for signed-in sites' do
    @site.update tutorial_required: false

    TUTORIAL_SECTIONS.each do |section|
      1.upto(TUTORIAL_PAGE_COUNT) do |page|
        get "/tutorial/#{section}/#{page}", {}, session_env('abcd', walked_to(section, [page, TUTORIAL_COMPLETION_PAGE].min))
        _(last_response.status).must_equal 200, "expected 200 for #{section} page #{page}"
        _(last_response.body).must_include "<h1>#{CGI.escapeHTML tutorial_page_title(section, page)}</h1>"
        _(last_response.body).must_include 'aria-current="step"'
        _(last_response.body).wont_include 'aria-current=&quot;'
      end
    end
  end

  it 'keeps tokens out of urls while giving everyone the advance form' do
    @site.update tutorial_required: false

    TUTORIAL_SECTIONS.each do |section|
      get "/tutorial/#{section}/#{TUTORIAL_COMPLETION_PAGE - 1}", {}, session_env('abcd', walked_to(section, TUTORIAL_COMPLETION_PAGE - 1))

      _(last_response.status).must_equal 200
      _(last_response.body).must_include 'id="advanceForm"'
      _(last_response.body).wont_include '?csrf_token='
    end
  end

  it 'escapes the starter html inside the editor container' do
    @site.update tutorial_required: false

    get '/tutorial/html/2', {}, session_env('abcd', walked_to('html', 2))

    _(last_response.status).must_equal 200
    _(last_response.body).must_include '<div id="editor" class="editor">&lt;!DOCTYPE html&gt;'
    _(last_response.body).wont_include '<div id="editor" class="editor"><!DOCTYPE html>'
    _(last_response.body).must_include %q{var defaultTutorialHtml = '<!DOCTYPE html>\n<html>}
    _(last_response.body).wont_include %q{var defaultTutorialHtml = '&lt;!DOCTYPE html&gt;}
  end

  it 'shares one storage key per section so work flows between pages' do
    @site.update tutorial_required: false

    get '/tutorial/html/3', {}, session_env('abcd', walked_to('html', 3))
    _(last_response.body).must_include "storageKey: 'neocities_tutorial_html:#{@site.username}'"

    get '/tutorial/css/4', {}, session_env('abcd', walked_to('css', 4))
    _(last_response.body).must_include "storageKey: 'neocities_tutorial_css:#{@site.username}'"
    _(last_response.body).wont_include 'neocities_tutorial_css_4'
  end

  it 'only enables preview scripts for the js section' do
    @site.update tutorial_required: false

    get '/tutorial/css/1', {}, session_env
    _(last_response.body).must_include 'sandbox="allow-same-origin"'

    get '/tutorial/js/1', {}, session_env
    _(last_response.body).must_include 'sandbox="allow-scripts"'
    _(last_response.body).wont_include 'sandbox="allow-scripts allow-same-origin"'
  end

  it 'offers the index.html save only in the html tutorial, only for unchanged sites' do
    @site.update tutorial_required: false

    get '/tutorial/html/9', {}, session_env('abcd', walked_to('html', 9))
    _(last_response.body).must_include 'saveToSite'

    @site.update site_changed: true
    get '/tutorial/html/9', {}, session_env('abcd', walked_to('html', 9))
    _(last_response.status).must_equal 200
    _(last_response.body).wont_include 'saveToSite'

    get '/tutorial/css/9', {}, session_env('abcd', walked_to('css', 9))
    _(last_response.body).wont_include 'saveToSite'

    get '/tutorial/js/9', {}, session_env('abcd', walked_to('js', 9))
    _(last_response.body).wont_include 'saveToSite'
  end

  it 'serves each section one starter document for every page' do
    TUTORIAL_SECTIONS.each do |section|
      starter = tutorial_starter_html(section)
      _(starter).must_include '<!DOCTYPE html>', "#{section} starter should be a full document"
      _(starter).must_include '</html>'

      1.upto(TUTORIAL_PAGE_COUNT) do |page|
        _(tutorial_starter_html(section, page)).must_equal starter
      end
    end
  end

  it 'gives each section a starter its first lesson can work on' do
    _(tutorial_starter_html('html')).must_include 'Hello World!'
    _(tutorial_starter_html('html')).wont_include '<h1>'

    _(tutorial_starter_html('html2')).must_include '<p>'
    _(tutorial_starter_html('html2')).wont_include '<strong>'

    _(tutorial_starter_html('css')).must_include '<style>'
    _(tutorial_starter_html('css')).must_include 'background-color:'
    _(tutorial_starter_html('css')).wont_include 'h1 {'

    _(tutorial_starter_html('js')).must_include 'linear-gradient'
    _(tutorial_starter_html('js')).wont_include '<script>'
  end
end
