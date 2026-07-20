# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

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

      it 'defaults new sites to list view' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow

        page.set_rack_session id: @site.id
        visit '/dashboard'
        page.execute_script("localStorage.removeItem('viewType')")
        refresh

        _(page).must_have_css('#filesDisplay.list-view')
      end

      it 'preserves user view preferences' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow

        page.set_rack_session id: @site.id
        visit '/dashboard'
        page.execute_script("localStorage.setItem('viewType', 'list')")
        refresh
        _(page).must_have_css('#filesDisplay.list-view')

        page.execute_script("localStorage.setItem('viewType', 'icon')")
        refresh
        _(page).wont_have_css('#filesDisplay.list-view')
      end

      it 'creates a top-level directory' do
        visit '/dashboard'
        click_link 'New Folder'
        fill_in 'name', with: 'testdir'
        #click_button 'Create'
        all('#createDir button[type=submit]').first.click
        _(page).must_have_content /testdir/
        _(File.directory?(@site.files_path('testdir'))).must_equal true
      end

      it 'creates a nested directory' do
        @site.create_directory 'testdirone'
        visit '/dashboard'
        click_link 'testdirone'
        click_link 'New Folder'
        _(find('#newDirInput').value.to_s).must_equal ''
        fill_in 'name', with: 'testdirtwo'
        all('#createDir button[type=submit]').first.click
        _(page).must_have_content /testdirtwo/
        _(File.directory?(@site.files_path('testdirone/testdirtwo'))).must_equal true
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

      it 'blocks duplicate new file submissions while create is pending' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow
        random = SecureRandom.uuid.gsub('-', '')

        page.set_rack_session id: @site.id
        visit '/dashboard'
        click_link 'New File'
        _(page).must_have_css('#createFile', visible: true)
        fill_in 'filename', with: "#{random}.html"

        page.execute_script <<~JS
          window.createFileRequestCount = 0;
          $.ajax = function(options) {
            window.createFileRequestCount += 1;
            window.pendingCreateFileRequest = options;
          };
        JS

        find('#createFileSubmitButton').click
        _(page).must_have_css('#createFileSubmitButton[disabled]')

        page.execute_script('handleCreateFile(); handleCreateFile();')
        _(page.evaluate_script('window.createFileRequestCount')).must_equal 1

        page.execute_script <<~JS
          window.pendingCreateFileRequest.error({
            responseText: JSON.stringify({message: 'Failed to create file'})
          });
        JS

        _(page).wont_have_css('#createFileSubmitButton[disabled]')
      end

      it 'deletes multiple files through the API from the dashboard' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow
        @site.store_files [
          {filename: 'bulk-one.txt', tempfile: Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')},
          {filename: 'bulk-two.txt', tempfile: Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')}
        ]

        page.set_rack_session id: @site.id
        visit '/dashboard'

        click_button 'Select'
        find('.bulk-select-control[title="Select bulk-one.txt"]').click
        find('.bulk-select-control[title="Select bulk-two.txt"]').click
        click_button 'Delete selected'

        _(page).must_have_css('#deleteConfirmModal', visible: true)
        within '#deleteConfirmModal' do
          click_button 'Delete'
        end

        _(page).must_have_content('2 items have been deleted.')
        _(page).wont_have_content('bulk-one.txt')
        _(page).wont_have_content('bulk-two.txt')
        _(File.exist?(@site.files_path('bulk-one.txt'))).must_equal false
        _(File.exist?(@site.files_path('bulk-two.txt'))).must_equal false
      end

      it 'shows bulk delete progress and blocks duplicate submissions' do
        Capybara.default_driver = :selenium_chrome_headless_largewindow
        @site.store_files [
          {filename: 'pending-one.txt', tempfile: Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')},
          {filename: 'pending-two.txt', tempfile: Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')}
        ]

        page.set_rack_session id: @site.id
        visit '/dashboard'

        click_button 'Select'
        find('.bulk-select-control[title="Select pending-one.txt"]').click
        find('.bulk-select-control[title="Select pending-two.txt"]').click
        click_button 'Delete selected'

        _(page).must_have_css('#deleteConfirmModal', visible: true)
        page.execute_script <<~JS
          window.deleteRequestCount = 0;
          $.ajax = function(options) {
            window.deleteRequestCount += 1;
            window.pendingDeleteRequest = options;
          };
        JS

        within '#deleteConfirmModal' do
          click_button 'Delete'
        end

        _(page).must_have_css('#deleteConfirmButton[disabled]', text: 'Deleting...')
        _(page).must_have_css('#deleteProgressMessage', text: 'Deleting 2 items...', visible: true)

        page.execute_script('fileDelete()')
        _(page.evaluate_script('window.deleteRequestCount')).must_equal 1
      end
    end
  end
end
