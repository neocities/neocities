# frozen_string_literal: true
require_relative './environment.rb'

describe 'signup' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def fill_in_valid
    @site = Fabricate.attributes_for(:site)
    _(page).must_have_content 'Sign up for free'
    fill_in 'username', with: @site[:username]
    fill_in 'password', with: @site[:password]
    fill_in 'email',    with: @site[:email]
  end

  def click_signup_button
    click_button 'Create My Site'
  end

  def site_created?
    _(page).must_have_content 'Welcome to Neocities'
  end

  def visit_signup
    visit '/'
  end

  before do
    reset_signup
  end

  def reset_signup
    Capybara.default_driver = :selenium_chrome_headless_largewindow
    Capybara.reset_sessions!
    visit_signup
    unless page.has_content?('Sign up for free')
      page.driver.browser.manage.delete_all_cookies
      visit_signup
    end
    _(page).must_have_content 'Sign up for free'
  end

  after do
    Capybara.default_driver = :rack_test
    BlockedIp.where(ip: '127.0.0.1').delete
    DB[:sites].where(is_banned: true).delete
  end

  it 'succeeds with valid data' do
    fill_in_valid
    click_signup_button
    site_created?
    click_link 'Continue'
    _(current_path).must_equal "/site/#{@site[:username]}/confirm_email"
    _(page).must_have_content /almost ready!/
    fill_in 'token', with: Site[username: @site[:username]].email_confirmation_token
    click_button 'Confirm Email'
    _(page).must_have_content /Let's Get Started/
    _(current_path).must_equal '/tutorial'
    index_file_path = File.join Site::SITE_FILES_ROOT, Site.sharding_dir(@site[:username]), @site[:username], 'index.html'
    _(File.exist?(index_file_path)).must_equal true

    site = Site[username: @site[:username]]
    _(site.site_files.length).must_equal 5
    _(site.site_changed).must_equal false
    _(site.site_updated_at).must_be_nil
    _(site.is_education).must_equal false

    _(site.ip).must_equal '127.0.0.1'
  end

  it 'fails if site with same ip has been banned' do
    @banned_site = Fabricate :site, ip: '127.0.0.1'
    @banned_site.ban!
    fill_in_valid
    click_signup_button
    site = Site[username: @site[:username]]
    _(Site[username: @site[:username]]).must_be_nil
    _(current_path).must_equal '/'
    _(page).wont_have_content 'Welcome to Neocities'
    @banned_site.update ip: nil
  end

  it 'fails if IP is banned from blocked ips list' do
    DB[:blocked_ips].insert(ip: '127.0.0.1', created_at: Time.now)
    fill_in_valid
    click_signup_button
    _(Site[username: @site[:username]]).must_be_nil
    _(current_path).must_equal '/'
    _(page).wont_have_content 'Welcome to Neocities'
  end

  it 'fails to create for existing site' do
    @existing_site = Fabricate :site
    fill_in_valid
    fill_in 'username', with: @existing_site.username
    click_signup_button
    _(page).must_have_content 'already taken'
  end

  it 'fails with missing password' do
    fill_in_valid
    fill_in 'password', with: ''
    click_signup_button
    _(page).must_have_content 'Password must be at least 5 characters'
  end

  it 'fails with short password' do
    fill_in_valid
    fill_in 'password', with: 'derp'
    click_signup_button
    _(page).must_have_content 'Password must be at least 5 characters'
  end

  it 'fails with invalid hostname for username' do
    fill_in_valid
    fill_in 'username', with: '|\|0p|E'
    click_signup_button
    _(page).must_have_content 'Usernames can only contain'
    reset_signup
    fill_in_valid
    fill_in 'username', with: 'nope-'
    click_signup_button
    _(page).must_have_content 'Usernames can only contain'
    reset_signup
    fill_in_valid
    fill_in 'username', with: '-nope'
    click_signup_button
    _(page).must_have_content 'Usernames can only contain'
  end

  it 'fails with username greater than 32 characters' do
    fill_in_valid
    fill_in 'username', with: SecureRandom.hex+'1'
    click_signup_button
    _(page).must_have_content 'cannot exceed 32 characters'
  end

  it 'fails with existing email' do
    email = Fabricate.attributes_for(:site)[:email]
    fill_in_valid
    fill_in 'email', with: email
    click_signup_button
    _(site_created?).must_equal true
    Capybara.reset_sessions!
    visit_signup
    fill_in_valid
    fill_in 'email', with: email
    click_signup_button
    _(page).must_have_content /email.+exists/
  end

  it 'fails with existing email even if case sensitive' do
    email = Fabricate.attributes_for(:site)[:email]
    fill_in_valid
    fill_in 'email', with: email
    click_signup_button
    _(site_created?).must_equal true
    Capybara.reset_sessions!
    visit_signup
    fill_in_valid
    fill_in 'email', with: email.upcase
    click_signup_button
    _(page).must_have_content /email.+exists/
  end

  it 'succeeds with no tags' do
    fill_in_valid
    fill_in 'new_tags_string', with: ''
    click_signup_button
    _(site_created?).must_equal true
  end

  it 'succeeds with a single tag' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'derpie'
    click_signup_button
    _(site_created?).must_equal true
    _(Site.last.tags.first.name).must_equal 'derpie'
  end

  it 'succeeds with valid tags' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'derpie, shoujo'
    click_signup_button
    _(site_created?).must_equal true
    _(Site.last.tags.collect {|t| t.name}).must_equal ['derpie', 'shoujo']
  end

  it 'succeeds with extra space in tags' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'blinkies, music, programming, '
    click_signup_button
    _(site_created?).must_equal true
    _(Site.last.tags.collect {|t| t.name}).must_equal ['blinkies', 'music', 'programming']
  end

  it 'fails with invalid tag chars' do
    fill_in_valid
    fill_in 'new_tags_string', with: '$POLICE OFFICER$$$$$, derp'
    click_signup_button
    _(page).must_have_content /Tag.+can only contain/
  end

  it 'fails for tag with too many spaces' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'police    officer, hi'
    click_signup_button
    _(page).must_have_content /Tag.+cannot have spaces/
  end

  it 'fails for tag with too many words' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'police officer'
    click_signup_button
    _(page).must_have_content /Tag.+cannot be more than #{Tag::NAME_WORDS_MAX} word/
  end

  it "fails for tag longer than #{Tag::NAME_LENGTH_MAX} characters" do
    fill_in_valid
    fill_in 'new_tags_string', with: SecureRandom.hex(Tag::NAME_LENGTH_MAX)
    click_signup_button
    _(page).must_have_content /cannot be longer than #{Tag::NAME_LENGTH_MAX}/
  end

  it 'fails for too many tags' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'one, two, three, four, five, six'
    click_signup_button
    _(page).must_have_content /Cannot have more than \d tags for your site/
  end

  it 'does not duplicate tags' do
    fill_in_valid
    fill_in 'new_tags_string', with: 'one, one'
    click_signup_button

    _(page).must_have_content /Welcome to Neocities/

    site = Site[username: @site[:username]]
    _(site.tags.length).must_equal 1
    _(site.tags.first.name).must_equal 'one'
  end
end
