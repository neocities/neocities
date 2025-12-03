# frozen_string_literal: true
require_relative './environment.rb'

describe '/admin' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  before do
    Capybara.reset_sessions!
    @admin = Fabricate :site, is_admin: true
    page.set_rack_session id: @admin.id
    visit '/admin'
  end

  describe 'permissions' do
    include Capybara::DSL

    it 'works for admin site' do
      _(page.body).must_match /Admin/
    end

    it 'blocks all /admin paths for non-admin users' do
      non_admin_site = Fabricate :site
      page.set_rack_session id: non_admin_site.id
      
      # Test GET routes
      ['/admin', '/admin/reports', '/admin/usage', '/admin/email', '/admin/stats', '/admin/masquerade/test'].each do |path|
        visit path
        _(page.current_path).must_equal '/', "Failed to block GET #{path}"
      end
      
      # Test POST routes
      ['/admin/reports', '/admin/ban', '/admin/unban', '/admin/mark_nsfw', '/admin/feature', '/admin/email'].each do |path|
        page.driver.post path, {}
        _(page.driver.status_code).must_equal 302, "Expected redirect for POST #{path}"
        
        # Follow the redirect and verify we end up at home page (blocked)
        visit page.driver.response_headers['Location'] if page.driver.response_headers['Location']
        _(page.current_path).must_equal '/', "POST #{path} should redirect to home page, not #{page.current_path}"
      end
    end

    it 'blocks /admin paths for signed out users' do
      page.set_rack_session id: nil
      
      visit '/admin'
      _(page.current_path).must_equal '/'
      
      page.driver.post '/admin/ban', {usernames: 'test'}
      _(page.driver.status_code).must_equal 302
      
      # Follow the redirect and verify we end up at home page (blocked)
      visit page.driver.response_headers['Location'] if page.driver.response_headers['Location']
      _(page.current_path).must_equal '/', "Signed out user POST should redirect to home page"
    end
  end

  describe 'supporter upgrade' do
    include Capybara::DSL

    it 'works for valid site' do
      site = Fabricate :site

      within(:css, '#upgradeToSupporter') do
        fill_in 'username', with: site.username
        click_button 'Upgrade to Supporter'
        site.reload
        _(site.stripe_customer_id).wont_be_nil
        _(site.stripe_subscription_id).wont_be_nil
        _(site.values[:plan_type]).must_equal 'special'
        _(site.supporter?).must_equal true
      end
    end

  end

  describe 'ban site form' do
    include Capybara::DSL

    it 'bans single site successfully' do
      site_to_ban = Fabricate :site
      
      fill_in 'usernames', with: site_to_ban.username
      # select 'Spam', from: 'classifier'
      click_button 'Ban'
      
      site_to_ban.reload
      _(site_to_ban.is_banned).must_equal true
      _(page.body).must_match(/sites have been banned/)
    end

    it 'bans multiple sites successfully' do
      site1 = Fabricate :site
      site2 = Fabricate :site
      
      fill_in 'usernames', with: "#{site1.username}\n#{site2.username}"
      #select 'Phishing', from: 'classifier'
      click_button 'Ban'
      
      site1.reload
      site2.reload
      _(site1.is_banned).must_equal true
      _(site2.is_banned).must_equal true
      _(page.body).must_match(/sites have been banned/)
    end

    it 'bans sites using IP when checkbox is checked' do
      ip_address = '192.168.1.1'
      site1 = Fabricate :site, ip: ip_address
      site2 = Fabricate :site, ip: ip_address
      
      fill_in 'usernames', with: site1.username
      check 'ban_using_ips'
      select 'Spam', from: 'classifier'
      click_button 'Ban'
      
      site1.reload
      site2.reload
      _(site1.is_banned).must_equal true
      _(site2.is_banned).must_equal true
    end
  end

  describe 'unban site form' do
    include Capybara::DSL

    before do
      @banned_site = Fabricate :site, is_banned: true
    end

    it 'unbans site successfully' do
      within(:css, 'form[action="/admin/unban"]') do
        fill_in 'username', with: @banned_site.username
        click_button 'Unban'
      end
      
      @banned_site.reload
      _(@banned_site.is_banned).must_equal false
      _(page.body).must_match(/was unbanned/)
    end

    it 'handles non-existent username gracefully' do
      within(:css, 'form[action="/admin/unban"]') do
        fill_in 'username', with: 'nonexistent_user'
        click_button 'Unban'
      end
      
      _(page.body).must_match(/User not found/)
    end
  end

  describe 'mark as NSFW form' do
    include Capybara::DSL

    it 'marks site as NSFW successfully' do
      site_to_mark = Fabricate :site
      
      within(:css, 'form[action="/admin/mark_nsfw"]') do
        fill_in 'username', with: site_to_mark.username
        click_button 'Mark NSFW'
      end
      
      site_to_mark.reload
      _(site_to_mark.is_nsfw).must_equal true
      _(page.body).must_match(/MISSION ACCOMPLISHED/)
    end

    it 'handles non-existent username gracefully' do
      within(:css, 'form[action="/admin/mark_nsfw"]') do
        fill_in 'username', with: 'nonexistent_user'
        click_button 'Mark NSFW'
      end
      
      _(page.body).must_match(/User not found/)
    end
  end

  describe 'feature site form' do
    include Capybara::DSL

    it 'features site successfully' do
      site_to_feature = Fabricate :site
      
      within(:css, '#featureSite') do
        fill_in 'username', with: site_to_feature.username
        click_button 'Feature Site'
      end
      
      site_to_feature.reload
      _(site_to_feature.featured_at).wont_be_nil
      _(page.body).must_match(/Site has been featured/)
    end

    it 'handles non-existent username gracefully' do
      within(:css, '#featureSite') do
        fill_in 'username', with: 'nonexistent_user'
        click_button 'Feature Site'
      end
      
      _(page.body).must_match(/User not found/)
    end
  end

  describe 'site info lookup' do
    include Capybara::DSL

    it 'finds sites by username, email, domain, and urls' do
      username_site = Fabricate :site, username: 'plainuser'
      email_site = Fabricate :site, username: 'emailuser', email: 'user@gmail.com'
      domain_site = Fabricate :site, username: 'domainsite', domain: 'domain.com'
      neocities_site = Fabricate :site, username: 'derp'

      [
        ['plainuser', username_site.username],
        ['user@gmail.com', email_site.username],
        ['derp.neocities.org', neocities_site.username],
        ['domain.com', domain_site.username],
        ['https://domain.com/some/path', domain_site.username],
        ['https://derp.neocities.org/anything', neocities_site.username]
      ].each do |input, expected_username|
        visit "/admin/site/#{input}"
        _(page.body).must_match(/Site Info: #{Regexp.quote(expected_username)}/, "input #{input} current_path #{page.current_path}")
      end
    end
  end

  describe 'email blasting' do
    before do
      EmailWorker.jobs.clear
      @admin_site = Fabricate :site, is_admin: true
    end

    it 'works' do
      DB['update sites set changed_count=?', 0].first
      relevant_emails = []

      sites_emailed_count = Site::EMAIL_BLAST_MAXIMUM_PER_DAY*2

      sites_emailed_count.times {
        site = Fabricate :site, updated_at: Time.now, changed_count: 1
        relevant_emails << site.email
      }

      EmailWorker.jobs.clear

      time = Time.now

      Timecop.freeze(time) do
        visit '/admin/email'
        fill_in 'subject', with: 'Subject Test'
        fill_in 'body', with: 'Body Test'
        click_button 'Send'

        relevant_jobs = EmailWorker.jobs.select{|j| relevant_emails.include?(j['args'].first['to']) }
        _(relevant_jobs.length).must_equal sites_emailed_count

        relevant_jobs.each do |job|
          args = job['args'].first
          _(args['from']).must_equal 'Neocities <noreply@neocities.org>'
          _(args['subject']).must_equal 'Subject Test'
          _(args['body']).must_equal 'Body Test'
        end

        _(relevant_jobs.select {|j| j['at'].nil? || j['at'] == Time.now.to_f}.length).must_equal 1
        _(relevant_jobs.select {|j| j['at'] == (Time.now + 0.5).to_f}.length).must_equal 1

        _(relevant_jobs.select {|j| j['at'] == (time+1.day.to_i).to_f}.length).must_equal 1
        _(relevant_jobs.select {|j| j['at'] == (time+1.day.to_i+0.5).to_f}.length).must_equal 1
      end
    end
  end

  describe '/admin/reports' do
    include Capybara::DSL

    before do
      Capybara.current_driver = :selenium_chrome_headless_largewindow
      
      @admin = Fabricate :site, is_admin: true
      page.set_rack_session id: @admin.id
      
      @reported_site = Fabricate :site
      @reporting_site = Fabricate :site
      @report = Report.create(
        site: @reported_site,
        reporting_site: @reporting_site,
        type: 'inappropriate',
        comments: 'Test report comment',
        site_file_path: 'test.html'
      )
    end

    after do
      Capybara.use_default_driver
    end

    it 'displays reports page' do
      visit '/admin/reports'
      _(page.body).must_match /Site Reports/
      _(page.body).must_match @reported_site.username
      _(page.body).must_match /inappropriate/i
      _(page.body).must_match /Test report comment/
    end

    it 'displays anonymous reports without reporter' do
      # Clear existing reports to avoid interference
      Report.where(site: @reported_site).destroy
      
      anonymous_report = Report.create(
        site: @reported_site,
        reporting_site: nil,
        type: 'spam',
        comments: 'Anonymous report unique text'
      )

      visit '/admin/reports'
      _(page.body).must_match /Anonymous report unique text/
      
      within("#report-#{anonymous_report.id}") do
        _(page).wont_have_content 'reported by'
      end
    end

    it 'handles reports without site_file_path (defaults to index.html)' do
      no_path_report = Report.create(
        site: @reported_site,
        reporting_site: @reporting_site,
        type: 'phishing',
        comments: 'No specific file path',
        site_file_path: nil
      )

      visit '/admin/reports'
      _(page.body).must_match /No specific file path/
      _(page.body).must_match /index\.html/
    end

    it 'handles reports with empty site_file_path' do
      empty_path_report = Report.create(
        site: @reported_site,
        reporting_site: @reporting_site,
        type: 'malware',
        comments: 'Empty file path',
        site_file_path: ''
      )

      visit '/admin/reports'
      _(page.body).must_match /Empty file path/
      _(page.body).must_match /index\.html/
    end

    it 'filters out banned sites' do
      banned_site = Fabricate :site, is_banned: true
      banned_report = Report.create(
        site: banned_site,
        reporting_site: @reporting_site,
        type: 'spam',
        comments: 'Should not appear'
      )

      visit '/admin/reports'
      _(page.body).wont_match banned_site.username
      _(page.body).wont_match /Should not appear/
    end

    it 'filters out deleted sites' do
      deleted_site = Fabricate :site, is_deleted: true
      deleted_report = Report.create(
        site: deleted_site,
        reporting_site: @reporting_site,
        type: 'phishing',
        comments: 'Should not appear either'
      )

      visit '/admin/reports'
      _(page.body).wont_match deleted_site.username
      _(page.body).wont_match /Should not appear either/
    end

    it 'shows action buttons for each report' do
      visit '/admin/reports'
      
      within("#report-#{@report.id}") do
        _(page).must_have_button 'Ban Site'
        _(page).must_have_button 'Mark NSFW'
        _(page).must_have_button 'Dismiss'
      end
    end

    it 'hides Mark NSFW button for already NSFW sites' do
      @reported_site.update(is_nsfw: true)
      
      visit '/admin/reports'
      
      within("#report-#{@report.id}") do
        _(page).must_have_button 'Ban Site'
        _(page).wont_have_button 'Mark NSFW'
        _(page).must_have_button 'Dismiss'
      end
    end
  end




end
