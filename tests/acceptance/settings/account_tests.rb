require_relative '../environment.rb'

describe 'site/settings' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

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

      fill_in 'token', with: @site.reload.email_confirmation_token
      click_button 'Confirm Email'

      _(page).must_have_content /Email address changed/i

      @site.reload
      _(@site.email).must_equal @new_email
      _(@site.password_reset_token).must_be_nil

      _(EmailWorker.jobs.length).must_equal 2

      args = EmailWorker.jobs.select {|job| job['args'].first['subject'] =~ /confirm your email address/i}.first['args'].first
      _(args['to']).must_equal @new_email
      _(args['subject']).must_match /confirm your email address/i
      _(args['body']).must_match /hello #{@site.username}/i
      _(args['body']).must_match /#{@site.email_confirmation_token}/

      args = EmailWorker.jobs.select {|job| job['args'].first['subject'] =~ /your email address.+changed/i}.first['args'].first
      _(args['body']).must_match /previous email.+#{original_email}/
      _(args['body']).must_match /new email.+#{@site.email}/
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
