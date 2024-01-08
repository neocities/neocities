require_relative './environment.rb'

describe 'signup' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def fill_in_valid
    @site = Fabricate.attributes_for(:site)
    @class_tag = "mrteacher" # SecureRandom.uuid.gsub('-', '')[0..Tag::NAME_LENGTH_MAX-1]
    fill_in 'username',        with: @site[:username]
    fill_in 'password',        with: @site[:password]
    fill_in 'email',           with: @site[:email]
    fill_in 'new_tags_string', with: @class_tag
  end

  before do
    Capybara.default_driver = :selenium_chrome_headless
    Capybara.reset_sessions!
    visit '/education'
    _(page).must_have_content 'Neocities' # Used to force load wait
  end

  after do
    Capybara.default_driver = :rack_test
  end

  it 'fails for unwhitelisted tag' do
    @site = Fabricate.attributes_for :site
    @class_tag = "mrteacher" # SecureRandom.uuid.gsub('-', '')[0..Tag::NAME_LENGTH_MAX-1]
    fill_in 'username',        with: @site[:username]
    fill_in 'password',        with: @site[:password]
    fill_in 'email',           with: @site[:email]
    fill_in 'new_tags_string', with: 'nope'
    click_button 'Create My Site'
    _(page).wont_have_content /Let's Get Started/
  end

  it 'succeeds with valid data' do
    fill_in_valid
    click_button 'Create My Site'
    _(page).must_have_content /Let's Get Started/

    index_file_path = File.join Site::SITE_FILES_ROOT, Site.sharding_dir(@site[:username]), @site[:username], 'index.html'
    _(File.exist?(index_file_path)).must_equal true

    site = Site[username: @site[:username]]
    _(site.site_files.length).must_equal 4
    _(site.site_changed).must_equal false
    _(site.site_updated_at).must_be_nil
    _(site.is_education).must_equal true
    _(site.tags.length).must_equal 1
    _(site.tags.first.name).must_equal @class_tag
  end

  it 'fails for multiple tags' do
    fill_in_valid
    fill_in :new_tags_string, with: 'derp, ie'
    click_button 'Create My Site'
    _(page).must_have_content 'Must only have one tag'
  end
end
