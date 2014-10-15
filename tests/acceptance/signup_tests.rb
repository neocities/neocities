require_relative './environment.rb'

describe 'signup' do
  include Capybara::DSL

  def fill_in_valid
    @site = Fabricate.attributes_for(:site)
    fill_in 'username', with: @site[:username]
    fill_in 'password', with: @site[:password]
    fill_in 'email',    with: @site[:email]
  end

  def visit_signup
    visit '/'
    click_button 'Create My Site'
  end

  before do
    Capybara.reset_sessions!
    visit_signup
  end

  it 'succeeds with valid data' do
    fill_in_valid
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
    assert_equal(
      true,
      File.exist?(File.join(Site::SITE_FILES_ROOT, @site[:username], 'index.html'))
    )
  end

  it 'fails to create for existing site' do
    fill_in_valid
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
    Capybara.reset_sessions!
    visit_signup
    fill_in 'username', with: @site[:username]
    fill_in 'password', with: @site[:password]
    click_button 'Create Home Page'
    page.must_have_content 'already taken'
  end

  it 'fails with missing password' do
    fill_in_valid
    fill_in 'password', with: ''
    click_button 'Create Home Page'
    page.must_have_content 'Password must be at least 5 characters'
  end

  it 'fails with short password' do
    fill_in_valid
    fill_in 'password', with: 'derp'
    click_button 'Create Home Page'
    page.must_have_content 'Password must be at least 5 characters'
  end

  it 'fails with invalid hostname for username' do
    fill_in_valid
    fill_in 'username', with: '|\|0p|E'
    click_button 'Create Home Page'
    page.current_path.must_equal '/create'
    page.must_have_content 'A valid user/site name is required'
    fill_in 'username', with: 'nope-'
    click_button 'Create Home Page'
    page.must_have_content 'A valid user/site name is required'
    fill_in 'username', with: '-nope'
    click_button 'Create Home Page'
    page.must_have_content 'A valid user/site name is required'
  end

  it 'fails with username greater than 32 characters' do
    fill_in_valid
    fill_in 'username', with: SecureRandom.hex+'1'
    click_button 'Create Home Page'
    page.must_have_content 'cannot exceed 32 characters'
  end

  it 'fails with invalid tag chars' do
    fill_in_valid
    fill_in 'tags', with: '$POLICE OFFICER$$$$$, derp'
    click_button 'Create Home Page'
    page.must_have_content /Tag.+can only contain/
  end

  it 'fails for tag with too many spaces' do
    fill_in_valid
    fill_in 'tags', with: 'police    officer, hi'
    click_button 'Create Home Page'
    page.must_have_content /Tag.+cannot have spaces/
  end

  it 'fails for tag with too many words' do
    fill_in_valid
    fill_in 'tags', with: 'police officer'
    click_button 'Create Home Page'
    page.must_have_content /Tag.+cannot be more than #{Tag::NAME_WORDS_MAX} word/
  end

  it "fails for tag longer than #{Tag::NAME_LENGTH_MAX} characters" do
    fill_in_valid
    fill_in 'tags', with: SecureRandom.hex(Tag::NAME_LENGTH_MAX)
    click_button 'Create Home Page'
    page.must_have_content /cannot be longer than #{Tag::NAME_LENGTH_MAX}/
  end

  it 'fails for too many tags' do
    fill_in_valid
    fill_in 'tags', with: 'one, two, three, four, five, six'
    click_button 'Create Home Page'
    page.must_have_content /Cannot have more than \d tags for your site/
  end

  it 'does not duplicate tags' do
    fill_in_valid
    fill_in 'tags', with: 'one, one'
    click_button 'Create Home Page'

    site = Site.last
    site.tags.length.must_equal 1
    site.tags.first.name.must_equal 'one'
  end

  it 'fails with existing email' do
    email = Fabricate.attributes_for(:site)[:email]
    fill_in_valid
    fill_in 'email', with: email
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
    Capybara.reset_sessions!
    visit_signup
    fill_in_valid
    fill_in 'email', with: email
    click_button 'Create Home Page'
    page.must_have_content /email.+exists/
  end

  it 'succeeds with no tags' do
    fill_in_valid
    fill_in 'tags', with: ''
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
  end

  it 'succeeds with a single tag' do
    fill_in_valid
    fill_in 'tags', with: 'derpie'
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
    Site.last.tags.first.name.must_equal 'derpie'
  end

  it 'succeeds with valid tags' do
    fill_in_valid
    fill_in 'tags', with: 'derpie, shoujo'
    click_button 'Create Home Page'
    page.must_have_content 'Your Feed'
    Site.last.tags.collect {|t| t.name}.must_equal ['derpie', 'shoujo']
  end
end