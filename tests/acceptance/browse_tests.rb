require_relative './environment.rb'

describe '/browse' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

=begin
  describe 'as admin' do
    before do
      DB[:sites_tags].delete
      DB[:sites].delete
      Capybara.reset_sessions!
      @admin = Fabricate :site, is_admin: true
      @site = Fabricate :site, site_changed: true
      page.set_rack_session id: @admin.id
    end

    it 'bans from browse for admin' do
      visit '/browse?sort_by=newest'
      within("li#username_#{@site.username} div.admin") do
        click_button 'Ban'
      end

      @site.reload.is_banned.must_equal true
      @admin.reload.is_banned.must_equal false
    end

    it 'bans for spam' do
      visit '/browse?sort_by=newest'
      within(".website-Gallery li#username_#{@site.username}") do
        click_button 'Spam'
      end

      sleep 1

      @site.reload.is_banned.must_equal true
      @site.site_files_dataset.where(path: 'index.html').first.classifier.must_equal 'spam'
    end

    it 'bans for phishing' do
      visit '/browse?sort_by=newest'
      within(".website-Gallery li#username_#{@site.username}") do
        click_button 'Phishing'
      end

      sleep 1

      @site.reload.is_banned.must_equal true
      @site.site_files_dataset.where(path: 'index.html').first.classifier.must_equal 'phishing'
    end
  end
=end
end
