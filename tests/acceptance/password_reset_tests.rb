require_relative './environment.rb'

describe '/password_reset' do
  include Capybara::DSL

  before do
    Capybara.reset_sessions!
    EmailWorker.jobs.clear
  end

  it 'should load the password reset page' do
    visit '/password_reset'
    page.body.must_match /Reset Password/
  end

  it 'should not load password reset if logged in' do
    @site = Fabricate :site
    page.set_rack_session id: @site.id

    visit '/password_reset'
    URI.parse(page.current_url).path.must_equal '/'
  end

  it 'errors for missing email' do
    visit '/password_reset'
    click_button 'Send Reset Token'
    URI.parse(page.current_url).path.must_equal '/password_reset'
    body.must_match /You must enter a valid email address/
  end

  it 'fails for invalid username or token' do
    @site = Fabricate :site
    visit '/password_reset'
    fill_in 'email', with: @site.email
    click_button 'Send Reset Token'

    @site.reload

    [
      {username: 'derp', token: @site.password_reset_token},
      {username: '', token: @site.password_reset_token},
      {username: @site.username, token: 'derp'},

      {token: 'derp'},

    ].each do |params|
      visit "/password_reset_confirm?#{Rack::Utils.build_query params}"
      page.must_have_content 'Could not find a site with this username and token'
      @site.reload.password_reset_confirmed.must_equal false
    end

    [
      {username: @site.username, token: ''},
      {username: @site.username},
      {username: '', token: ''}
    ].each do |params|
      visit "/password_reset_confirm?#{Rack::Utils.build_query params}"
      page.must_have_content 'Token cannot be empty'
      @site.reload.password_reset_confirmed.must_equal false
    end

  end

  it 'works for valid username and token' do
    @site = Fabricate :site
    visit '/password_reset'
    fill_in 'email', with: @site.email
    click_button 'Send Reset Token'

    body.must_match /send an e-mail to your account with password reset instructions/
    @site.reload.password_reset_token.blank?.must_equal false
    EmailWorker.jobs.first['args'].first['body'].must_match /#{Rack::Utils.build_query(username: @site.username, token: @site.password_reset_token)}/

    visit "/password_reset_confirm?#{Rack::Utils.build_query username: @site.username, token: @site.reload.password_reset_token}"

    page.current_url.must_match /.+\/settings$/

    fill_in 'new_password', with: 'n3wp4s$'
    fill_in 'new_password_confirm', with: 'n3wp4s$'
    click_button 'Change Password'

    page.current_url.must_match /.+\/settings$/
    page.must_have_content 'Successfully changed password'
    Site.valid_login?(@site.username, 'n3wp4s$').must_equal true
    page.get_rack_session['id'].must_equal @site.id
    @site.reload.password_reset_token.must_equal nil
    @site.password_reset_confirmed.must_equal false
  end

end
