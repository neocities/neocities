require_relative './environment.rb'

describe 'site/settings' do
  describe 'change username' do
    include Capybara::DSL

    def visit_signup
      visit '/'
      click_button 'Create My Website'
    end

    def fill_in_valid
      @site = Fabricate.attributes_for(:site)
      fill_in 'username', with: @site[:username]
      fill_in 'password', with: @site[:password]
      fill_in 'email',    with: @site[:email]
    end

    before do
      Capybara.reset_sessions!
      visit_signup
    end

    it 'does not allow bad usernames' do
      visit '/'
      click_button 'Create My Website'
      fill_in_valid
      click_button 'Create Home Page'
      visit '/settings'
      fill_in 'name', with: ''
      click_button 'Change Name'
      fill_in 'name', with: '../hack'
      click_button 'Change Name'
      fill_in 'name', with: 'derp../hack'
      click_button 'Change Name'
      ## TODO fix this without screwing up legacy sites
      #fill_in 'name', with: '-'
      #click_button 'Change Name'
      page.must_have_content /valid.+name.+required/i
      Site[username: @site[:username]].wont_equal nil
      Site[username: ''].must_equal nil
    end
  end
end