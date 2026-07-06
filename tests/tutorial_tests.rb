# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe 'tutorial' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session_env(token='abcd')
    {'rack.session' => {'id' => @site.id, '_csrf_token' => token}}
  end

  before do
    @site = Fabricate :site, tutorial_required: true
  end

  it 'redirects tutorial-required sites back to the tutorial' do
    get '/dashboard', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}
  end

  it 'requires login' do
    get '/tutorial/html/1'

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/\z}
  end

  it 'redirects the section index to the first page' do
    @site.update tutorial_required: false

    get '/tutorial/html', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/1\z}
  end

  it 'not founds unknown sections and out of range pages' do
    @site.update tutorial_required: false

    ['/tutorial/css/1', '/tutorial/html/0', "/tutorial/html/#{TUTORIAL_PAGE_COUNT + 1}", '/tutorial/html/banana', '/tutorial/html/01'].each do |path|
      get path, {}, session_env
      _(last_response.status).must_equal 404, "expected 404 for #{path}"
    end
  end

  it 'does not complete the required tutorial without csrf' do
    get '/tutorial/html/9', {}, session_env

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_match %r{/tutorial/html/8\z}
    _(@site.reload.tutorial_required).must_equal true
  end

  it 'completes the required tutorial at the review step with csrf' do
    get '/tutorial/html/9', {csrf_token: 'abcd'}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Review And Save'
    _(@site.reload.tutorial_required).must_equal false
  end

  it 'does not complete the tutorial on earlier pages' do
    1.upto(TUTORIAL_COMPLETION_PAGE - 1) do |page|
      get "/tutorial/html/#{page}", {}, session_env
      _(last_response.status).must_equal 200
      _(@site.reload.tutorial_required).must_equal true, "page #{page} should not complete the tutorial"
    end
  end

  it 'renders every html tutorial page for signed-in sites' do
    @site.update tutorial_required: false

    1.upto(TUTORIAL_PAGE_COUNT) do |page|
      page == TUTORIAL_COMPLETION_PAGE ? get("/tutorial/html/#{page}", {csrf_token: 'abcd'}, session_env) : get("/tutorial/html/#{page}", {}, session_env)
      _(last_response.status).must_equal 200, "expected 200 for page #{page}"
      _(last_response.body).must_include "<h1>#{tutorial_page_title(page)}</h1>"
      _(last_response.body).must_include 'aria-current="step"'
      _(last_response.body).wont_include 'aria-current=&quot;'
    end
  end

  it 'links the completion page with a csrf token from the previous page' do
    @site.update tutorial_required: false

    get "/tutorial/html/#{TUTORIAL_COMPLETION_PAGE - 1}", {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include "/tutorial/html/#{TUTORIAL_COMPLETION_PAGE}?csrf_token="
  end

  it 'escapes the starter html inside the editor container' do
    @site.update tutorial_required: false

    get '/tutorial/html/2', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include '<div id="editor" class="editor">&lt;!DOCTYPE html&gt;'
    _(last_response.body).wont_include '<div id="editor" class="editor"><!DOCTYPE html>'
    _(last_response.body).must_include %q{var defaultTutorialHtml = '<!DOCTYPE html>\n<html>}
    _(last_response.body).wont_include %q{var defaultTutorialHtml = '&lt;!DOCTYPE html&gt;}
  end

  it 'provides a starter document reflecting completed previous steps' do
    starter = tutorial_starter_html(1)
    _(starter).must_include 'Hello World!'
    _(starter).must_include '<title>My First Website</title>'
    _(starter).wont_include '<h1>'

    starter = tutorial_starter_html(TUTORIAL_COMPLETION_PAGE)
    _(starter).wont_include 'Hello World!'
    _(starter).must_include '<h1>My Website</h1>'
    _(starter).must_include '<title>My Corner of the Web</title>'
    _(starter).must_include '<a href="https://neocities.org">'
    _(starter).must_include '<img src="/neocities.png"'
    _(starter).must_include '<ul>'
    _(starter).must_include '<style>'
  end
end
