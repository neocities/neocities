require_relative './environment.rb'

describe 'dashboard' do
  describe 'create directory' do

    describe 'logged in' do
      include Capybara::DSL
      include Capybara::Minitest::Assertions

      before do
        Capybara.reset_sessions!
        @site = Fabricate :site
        page.set_rack_session id: @site.id
      end

      after do
        Capybara.default_driver = :rack_test
      end

      it 'records a dashboard access' do
        _(@site.reload.dashboard_accessed).must_equal false
        visit '/dashboard'
        _(@site.reload.dashboard_accessed).must_equal true
      end

      it 'creates a base directory' do
        visit '/dashboard'
        click_link 'New Folder'
        fill_in 'name', with: 'testimages'
        #click_button 'Create'
        all('#createDir button[type=submit]').first.click
        _(page).must_have_content /testimages/
        _(File.directory?(@site.files_path('testimages'))).must_equal true
      end

      it 'creates a new file' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow
        random = SecureRandom.uuid.gsub('-', '')
      
        page.set_rack_session id: @site.id
        visit '/dashboard'
        _(page).must_have_content('Home')
        _(page).must_have_link('New File')
        click_link 'New File'
        # Wait for modal to appear
        _(page).must_have_css('#createFile', visible: true)
        fill_in 'filename', with: "#{random}.html"
        find('#createFile .btn-Action').click
        # Wait for the file to appear in the listing
        _(page).must_have_content(/#{Regexp.escape(random)}\.html/)
        _(File.exist?(@site.files_path("#{random}.html"))).must_equal true
      end
    end
  end
end
