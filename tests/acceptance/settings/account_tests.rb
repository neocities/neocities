# frozen_string_literal: true
require_relative '../environment.rb'

describe 'site/settings' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  describe 'sites' do
    before do
      Capybara.reset_sessions!
      @parent_site = Fabricate :site
      @child_site = Fabricate :site, parent_site_id: @parent_site.id
      @other_site = Fabricate :site
      page.set_rack_session id: @parent_site.id
      visit '/settings'
    end

    it 'shows the current site and offers both switch interfaces' do
      parent_row = find('.settings-site-row', text: @parent_site.username)
      child_row = find('.settings-site-row', text: @child_site.username)

      _(parent_row).must_have_content 'Parent'
      _(parent_row).must_have_content 'Current'
      _(parent_row).wont_have_button 'Switch'
      _(child_row).must_have_button 'Switch'
      _(page).must_have_link 'Switch Site', href: '#siteSwitcher'
      _(page).wont_have_selector "a[href='/signin/#{@child_site.username}']"

      switcher = find('#siteSwitcher', visible: :all)
      _(switcher).must_have_selector '#siteSwitcherSearch', visible: :all
      _(switcher).must_have_selector(
        "form[action='/settings/#{@child_site.username}/switch'] input[name='csrf_token']",
        visible: :all
      )
      _(switcher).must_have_selector(
        "[data-site-switcher-row][aria-current='true']",
        text: @parent_site.username,
        visible: :all
      )
      [@parent_site, @child_site].each do |site|
        row = switcher.find(
          "[data-site-switcher-row][data-site-name^='#{site.username.downcase} ']",
          visible: :all
        )
        thumbnail = row.find('img.site-switcher-thumbnail', visible: :all)

        _(thumbnail[:src]).must_equal site.screenshot_url('index.html', '50x50')
        _(thumbnail[:alt]).must_equal ''
        _(thumbnail[:onerror]).must_equal "this.src='/img/50x50.png'"
      end
      _(switcher).must_have_link 'Manage sites', href: '/settings#sites', visible: :all
    end

    it 'switches between parent and child sites from the site list' do
      within('.settings-site-row', text: @child_site.username) do
        click_button 'Switch'
      end

      _(page.current_path).must_equal '/dashboard'
      _(page.get_rack_session['id']).must_equal @child_site.id

      visit '/settings'
      child_row = find('.settings-site-row', text: @child_site.username)
      _(child_row).must_have_content 'Current'
      _(child_row).wont_have_button 'Switch'

      within('.settings-site-row', text: @parent_site.username) do
        click_button 'Switch'
      end

      _(page.current_path).must_equal '/dashboard'
      _(page.get_rack_session['id']).must_equal @parent_site.id
    end

    it 'does not switch to a site owned by another account' do
      csrf = find(
        ".settings-site-list form[action='/settings/#{@child_site.username}/switch'] input[name='csrf_token']",
        visible: false
      ).value

      page.driver.post "/settings/#{@other_site.username}/switch", csrf_token: csrf

      _(page.driver.status_code).must_equal 302
      location = URI.parse page.driver.response_headers['Location']
      _(location.path).must_equal '/settings'
      _(location.fragment).must_equal 'sites'
      _(page.get_rack_session['id']).must_equal @parent_site.id
    end

    it 'does not switch to missing or deleted sites' do
      csrf = find(
        ".settings-site-list form[action='/settings/#{@child_site.username}/switch'] input[name='csrf_token']",
        visible: false
      ).value

      page.driver.post "/settings/#{SecureRandom.hex}/switch", csrf_token: csrf

      _(page.driver.status_code).must_equal 404
      _(page.get_rack_session['id']).must_equal @parent_site.id

      deleted_site = Fabricate :site, parent_site_id: @parent_site.id
      deleted_site.destroy
      page.driver.post "/settings/#{deleted_site.username}/switch", csrf_token: csrf

      _(page.driver.status_code).must_equal 404
      _(page.get_rack_session['id']).must_equal @parent_site.id
    end

    it 'requires a CSRF token to switch sites' do
      page.driver.post "/settings/#{@child_site.username}/switch"

      _(page.driver.status_code).must_equal 302
      _(URI.parse(page.driver.response_headers['Location']).path).must_equal '/'
      _(page.get_rack_session['id']).must_equal @parent_site.id
    end

    it 'does not switch sites with a GET request' do
      page.driver.get "/signin/#{@child_site.username}"

      _(page.driver.status_code).must_equal 404
      _(page.get_rack_session['id']).must_equal @parent_site.id
    end
  end

  describe 'supporter' do
    before do
      Capybara.reset_sessions!
      @site = Fabricate :site,
        plan_type: 'supporter',
        stripe_customer_id: 'cus_supporter',
        stripe_subscription_id: 'sub_supporter'
      page.set_rack_session id: @site.id
      visit '/settings'
    end

    it 'renders the membership confirmation outside the settings panel' do
      _(page).must_have_link 'End Supporter membership', href: '#endSupporterConfirm'

      dialog = find('#endSupporterConfirm', visible: :all)
      _(dialog[:role]).must_equal 'dialog'
      _(dialog['aria-labelledby']).must_equal 'endSupporterConfirmLabel'
      _(page).wont_have_selector '.settings-panel #endSupporterConfirm', visible: :all
    end
  end

  describe 'email' do
    before do
      EmailWorker.jobs.clear
      @email = "#{SecureRandom.uuid.gsub('-', '')}@exampleedsdfdsf.com"
      @site = Fabricate :site, email: @email
      page.set_rack_session id: @site.id
      visit '/settings'
    end

    it 'should change email' do
      original_email = @site.email
      @site.password_reset_token = 'shouldgoaway'
      @site.save
      @new_email = "#{SecureRandom.uuid.gsub('-', '')}@exampleedsdfdsf.com"
      fill_in 'email', with: @new_email
      click_button 'Change Email'

      _(page).must_have_content /enter the confirmation code here/
      _(page).wont_have_content 'With great power comes great responsibility'

      fill_in 'token', with: @site.reload.email_confirmation_token
      click_button 'Confirm Email'

      _(page).must_have_content /Email address changed/i

      @site.reload
      _(@site.email).must_equal @new_email
      _(@site.password_reset_token).must_be_nil

      history = SiteIdentifierHistory.where(
        site_id: @site.id,
        identifier_type: SiteIdentifierHistory::EMAIL
      ).first
      _(history.identifier).must_equal original_email

      _(EmailWorker.jobs.length).must_equal 2

      args = EmailWorker.jobs.select {|job| job['args'].first['subject'] =~ /confirm your email address/i}.first['args'].first
      _(args['to']).must_equal @new_email
      _(args['subject']).must_match /confirm your email address/i
      _(args['body']).must_match /hello #{@site.username}/i
      _(args['body']).must_match /#{@site.email_confirmation_token}/

      args = EmailWorker.jobs.select {|job| job['args'].first['subject'] =~ /your email address.+changed/i}.first['args'].first
      _(args['to']).must_equal original_email
      _(args['body']).must_match /previous email.+#{original_email}/
      _(args['body']).must_match /new email.+#{@site.email}/
    end

    it 'should notify the previous email when unsubscribed' do
      original_email = @site.email
      @site.update send_emails: false
      new_email = "#{SecureRandom.uuid.gsub('-', '')}@exampleedsdfdsf.com"

      fill_in 'email', with: new_email
      click_button 'Change Email'

      _(@site.reload.send_emails).must_equal false
      _(EmailWorker.jobs.length).must_equal 2

      confirmation = EmailWorker.jobs.find {|job| job['args'].first['subject'] =~ /confirm your email address/i}
      notification = EmailWorker.jobs.find {|job| job['args'].first['subject'] =~ /your email address.+changed/i}
      _(confirmation['args'].first['to']).must_equal new_email
      _(notification['args'].first['to']).must_equal original_email
    end

    it 'should fail for invalid email address' do
      @new_email = SecureRandom.uuid.gsub '-', ''
      fill_in 'email', with: @new_email
      click_button 'Change Email'
      _(page).must_have_content /a valid email address is required/i
      @site.reload
      _(@site.email).wont_equal @new_email
      _(EmailWorker.jobs.empty?).must_equal true
    end

    it 'should fail for existing email' do
      @existing_email = "#{SecureRandom.uuid.gsub('-', '')}@exampleedsdfdsf.com"
      @existing_site = Fabricate :site, email: @existing_email

      fill_in 'email', with: @existing_email
      click_button 'Change Email'
      _(page).must_have_content /this email address already exists on neocities/i
      @site.reload
      _(@site.email).wont_equal @new_email
      _(EmailWorker.jobs.empty?).must_equal true
    end

    it 'should update email preferences' do
      uncheck 'send_emails'
      uncheck 'send_comment_emails'
      uncheck 'send_follow_emails'

      _(@site.send_emails).must_equal true
      _(@site.send_comment_emails).must_equal true
      _(@site.send_follow_emails).must_equal true

      click_button 'Update Notification Settings'
      @site.reload
      _(@site.send_emails).must_equal false
      _(@site.send_comment_emails).must_equal false
      _(@site.send_follow_emails).must_equal false
    end
  end

  describe 'email review' do
    before do
      @site = Fabricate :site
      @site.update email_reviewed_at: nil
      page.set_rack_session id: @site.id
    end

    it 'prompts from the home page until the user confirms' do
      visit '/dashboard'

      _(page.current_path).must_equal '/dashboard'
      _(@site.reload.email_reviewed_at).must_be_nil

      visit '/'

      _(page.current_path).must_equal '/settings/email_review'
      _(page).must_have_content @site.email
      _(@site.reload.email_reviewed_at).must_be_nil

      click_button 'Yes, this is correct'

      _(page.current_path).must_equal '/'
      _(@site.reload.email_reviewed_at).wont_be_nil
    end

    it 'changes the email from the review page' do
      new_email = "#{SecureRandom.hex}@example.net"
      visit '/'

      fill_in 'New Email Address', with: new_email
      click_button 'Change Email Address'

      @site.reload
      _(@site.email).must_equal new_email
      _(@site.email_reviewed_at).wont_be_nil
      _(page.current_path).must_equal "/site/#{@site.username}/confirm_email"
    end

    it 'does not complete the review for an invalid email' do
      visit '/'
      fill_in 'New Email Address', with: 'not-an-email'
      click_button 'Change Email Address'

      _(page.current_path).must_equal '/settings/email_review'
      _(@site.reload.email_reviewed_at).must_be_nil
    end

    it 'prompts again after six months' do
      @site.update email_reviewed_at: 6.months.ago
      visit '/'

      _(page.current_path).must_equal '/settings/email_review'
    end
  end

  describe 'new account email review' do
    it 'does not prompt new accounts' do
      site = Fabricate :site
      page.set_rack_session id: site.id
      visit '/'

      _(page.current_path).must_equal '/'
    end
  end

  describe 'unsubscribe email' do
    before do
      @email = "#{SecureRandom.uuid.gsub('-', '')}@exampleedsdfdsf.com"
      @site = Fabricate :site, email: @email
      EmailWorker.jobs.clear
      Mail::TestMailer.deliveries.clear

      @params = {
        email: @site.email,
        token: Site.email_unsubscribe_token(@site.email)
      }
      @params_query = Rack::Utils.build_query(@params)

      @email_unsubscribe_url = "https://neocities.org/settings/unsubscribe_email?"+@params_query
      page.set_rack_session id: nil
    end

    it 'should redirect to settings page if logged in' do
      page.set_rack_session id: @site.id

    end

    it 'should unsubscribe for valid token' do
      @site.send_email subject: 'Hello', body: 'Okay'
      EmailWorker.drain
      email = Mail::TestMailer.deliveries.first

      _(email.body.to_s).must_match @email_unsubscribe_url
      _(@site.send_emails).must_equal true
      visit '/settings/unsubscribe_email?'+@params_query

      _(page.body).must_match /You have been successfully unsubscribed.+#{@site.email}/i

      _(@site.reload.send_emails).must_equal false
    end

    it 'should fail to subscribe for bad token' do

    end
  end

  describe 'change password' do
    before do
      EmailWorker.jobs.clear
      @site = Fabricate :site, password: 'derpie'
      page.set_rack_session id: @site.id
      visit '/settings'
    end

    it 'should change correctly' do
      fill_in 'current_password', with: 'derpie'
      fill_in 'new_password', with: 'derpie2'
      fill_in 'new_password_confirm', with: 'derpie2'
      click_button 'Change Password'

      _(page).must_have_content /successfully changed password/i
      @site.reload
      _(@site.valid_password?('derpie')).must_equal false
      _(@site.valid_password?('derpie2')).must_equal true

      _(EmailWorker.jobs.select {|job| job['args'].first['subject'] =~ /password has been changed/i}.length).must_equal 1
    end

    it 'should not change for invalid current password' do
      fill_in 'current_password', with: 'dademurphy'
      fill_in 'new_password', with: 'derpie2'
      fill_in 'new_password_confirm', with: 'derpie2'
      click_button 'Change Password'

      _(page).must_have_content /provided password does not match the current one/i
      @site.reload
      _(@site.valid_password?('derpie')).must_equal true
      _(@site.valid_password?('derpie2')).must_equal false

      _(EmailWorker.jobs.length).must_equal 0
    end
  end
end
