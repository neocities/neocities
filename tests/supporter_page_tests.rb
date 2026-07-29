# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe '/supporter page' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session_env
    {'rack.session' => {'id' => @site.id, '_csrf_token' => 'supporter-page-test'}}
  end

  it 'gives signed-out visitors a path to create or access an account' do
    get '/supporter'

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Help us keep the web weird.'
    _(last_response.body).must_include 'class="supporter-hero"'
    _(last_response.body).wont_include 'supporter-galaxy'
    _(last_response.body).wont_include 'requestAnimationFrame'
    _(last_response.body).must_include 'href="/#new"'
    _(last_response.body).must_include 'href="/signin"'
    _(last_response.body).wont_include 'id="upgradeForm"'
    _(last_response.body).wont_include 'https://js.stripe.com/v2/'
  end

  it 'shows the secure upgrade form to free members' do
    @site = Fabricate :site

    get '/supporter', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'id="upgradeForm"'
    _(last_response.body).must_include 'action="/supporter/update"'
    _(last_response.body).must_include 'value="supporter" name="plan_type"'
    _(last_response.body).must_include 'Upgrade for $5/month'
    _(last_response.body).must_include 'https://js.stripe.com/v2/'
  end

  it 'thanks current supporters without showing another checkout' do
    @site = Fabricate :site, plan_type: 'supporter'

    get '/supporter', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'Thanks for keeping the web weird.'
    _(last_response.body).must_include 'Go to your dashboard'
    _(last_response.body).wont_include 'id="upgradeForm"'
    _(last_response.body).wont_include 'https://js.stripe.com/v2/'
  end

  it 'welcomes new users with the supporter page and a free-plan continue' do
    @site = Fabricate :site

    get '/welcome', {}, session_env

    _(last_response.status).must_equal 200
    _(last_response.body).must_include "Welcome to Neocities, #{@site.username}!"
    _(last_response.body).must_include 'class="supporter-hero"'
    _(last_response.body).must_include 'Supporter ($5/mo)'
    _(last_response.body).must_include 'id="upgradeForm"'
    _(last_response.body).must_include 'Continue with the free plan'
    _(last_response.body).must_include 'href="/tutorial"'
  end
end
