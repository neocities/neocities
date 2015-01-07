require_relative '../environment.rb'

describe 'site/settings' do
  describe 'email' do
    include Capybara::DSL

    before do
      EmailWorker.jobs.clear
      @email = "#{SecureRandom.uuid.gsub('-', '')}@example.com"
      @site = Fabricate :site, email: @email
      page.set_rack_session id: @site.id
      visit '/settings'
    end

    it 'should change email' do
      @new_email = "#{SecureRandom.uuid.gsub('-', '')}@example.com"
      fill_in 'email', with: @new_email
      click_button 'Change Email'
      page.must_have_content /successfully changed email/i
      @site.reload
      @site.email.must_equal @new_email
      EmailWorker.jobs.length.must_equal 1
      args = EmailWorker.jobs.first['args'].first
      args['to'].must_equal @new_email
      args['subject'].must_match /confirm your email address/i
      args['body'].must_match /hello #{@site.username}/i
      args['body'].must_match /#{@site.email_confirmation_token}/
    end

    it 'should fail for invalid email address' do
      @new_email = SecureRandom.uuid.gsub '-', ''
      fill_in 'email', with: @new_email
      click_button 'Change Email'
      page.must_have_content /a valid email address is required/i
      @site.reload
      @site.email.wont_equal @new_email
      EmailWorker.jobs.empty?.must_equal true
    end

    it 'should fail for existing email' do
      @existing_email = "#{SecureRandom.uuid.gsub('-', '')}@example.com"
      @existing_site = Fabricate :site, email: @existing_email

      fill_in 'email', with: @existing_email
      click_button 'Change Email'
      page.must_have_content /this email address already exists on neocities/i
      @site.reload
      @site.email.wont_equal @new_email
      EmailWorker.jobs.empty?.must_equal true
    end

    it 'should update email preferences' do
      uncheck 'send_emails'
      uncheck 'send_comment_emails'
      uncheck 'send_follow_emails'

      @site.send_emails.must_equal true
      @site.send_comment_emails.must_equal true
      @site.send_follow_emails.must_equal true

      click_button 'Update Notification Settings'
      @site.reload
      @site.send_emails.must_equal false
      @site.send_comment_emails.must_equal false
      @site.send_follow_emails.must_equal false
    end
  end

  describe 'change password' do
    include Capybara::DSL

    before do
      @site = Fabricate :site, password: 'derpie'
      page.set_rack_session id: @site.id
      visit '/settings'
    end

    it 'should change correctly' do
      fill_in 'current_password', with: 'derpie'
      fill_in 'new_password', with: 'derpie2'
      fill_in 'new_password_confirm', with: 'derpie2'
      click_button 'Change Password'

      page.must_have_content /successfully changed password/i
      @site.reload
      @site.valid_password?('derpie').must_equal false
      @site.valid_password?('derpie2').must_equal true
    end

    it 'should not change for invalid current password' do
      fill_in 'current_password', with: 'dademurphy'
      fill_in 'new_password', with: 'derpie2'
      fill_in 'new_password_confirm', with: 'derpie2'
      click_button 'Change Password'

      page.must_have_content /provided password does not match the current one/i
      @site.reload
      @site.valid_password?('derpie').must_equal true
      @site.valid_password?('derpie2').must_equal false
    end
  end
end