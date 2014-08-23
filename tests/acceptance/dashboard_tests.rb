require_relative './environment.rb'

describe 'dashboard' do
  describe 'create directory' do

    describe 'logged in' do

      include Capybara::DSL

      before do
        Capybara.reset_sessions!
        @site = Fabricate :site
        page.set_rack_session id: @site.id
      end

      it 'creates a base directory' do
        visit '/dashboard'
        click_link 'New Folder'
        fill_in 'name', with: 'testimages'
        click_button 'Create'
        page.must_have_content /testimages/
        File.directory?(@site.files_path('testimages')).must_equal true
      end
    end
  end
end