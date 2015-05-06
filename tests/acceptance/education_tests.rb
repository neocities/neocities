require_relative './environment.rb'

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, js_errors: false)
end

describe 'signup' do
  include Capybara::DSL

  def fill_in_valid
    @site = Fabricate.attributes_for(:site)
    @class_tag = SecureRandom.uuid.gsub('-', '')[0..Tag::NAME_LENGTH_MAX-1]
    fill_in 'username',        with: @site[:username]
    fill_in 'password',        with: @site[:password]
    fill_in 'email',           with: @site[:email]
    fill_in 'new_tags_string', with: @class_tag
  end

  before do
    Capybara.default_driver = :poltergeist
    Capybara.reset_sessions!
    visit '/education'
    page.must_have_content 'Neocities' # Used to force load wait
  end

  after do
    Capybara.default_driver = :rack_test
  end

  it 'succeeds with valid data' do
    fill_in_valid
    click_button 'Create My Site'
    page.must_have_content 'Welcome to Neocities'

    index_file_path = File.join Site::SITE_FILES_ROOT, @site[:username], 'index.html'
    File.exist?(index_file_path).must_equal true

    site = Site[username: @site[:username]]
    site.site_files.length.must_equal 4
    site.site_changed.must_equal false
    site.site_updated_at.must_equal nil
    site.is_education.must_equal true
    site.tags.length.must_equal 1
    site.tags.first.name.must_equal @class_tag
  end

  it 'fails to create for existing site' do
    @existing_site = Fabricate :site
    fill_in_valid
    fill_in :username, with: @existing_site.username
    click_button 'Create My Site'
    page.must_have_content 'already taken'
  end

  it 'fails for multiple tags' do
    fill_in_valid
    fill_in :new_tags_string, with: 'derp, ie'
    click_button 'Create My Site'
    page.must_have_content 'Must only have one tag'
  end
end
