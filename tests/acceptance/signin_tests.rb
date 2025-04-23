require_relative './environment.rb'

describe 'signin' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def fill_in_valid
    @site = Fabricate.attributes_for :site
    fill_in 'username', with: @site[:username]
    fill_in 'password', with: @site[:password]
  end

  before do
    Capybara.reset_sessions!
  end

  it 'restores a deleted site' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    @site.destroy
    _(Dir.exist?(@site.files_path)).must_equal false
    _(Dir.exist?(@site.deleted_files_path)).must_equal true
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Restore Site'
    click_button 'Restore Site'
    _(Dir.exist?(@site.deleted_files_path)).must_equal false
    _(Dir.exist?(@site.files_path)).must_equal true
    _(@site.reload.is_deleted).must_equal false
  end

  it 'fails for invalid signin' do
    visit '/'
    click_link 'Sign In'
    _(page).must_have_content 'Welcome Back'
    fill_in_valid
    click_button 'Sign In'
    _(page).must_have_content 'Invalid login'
  end

  it 'fails for missing signin' do
    visit '/'
    click_link 'Sign In'
    auth = {username: SecureRandom.hex, password: Faker::Internet.password}
    fill_in 'username', with: auth[:username]
    fill_in 'password', with: auth[:password]
    click_button 'Sign In'
    _(page).must_have_content 'Invalid login'
  end

  it 'signs in with proper credentials' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with invalid case username' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.username.upcase
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with email' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.email
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with invalid case email' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.email.upcase
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Your Feed'
  end
end
