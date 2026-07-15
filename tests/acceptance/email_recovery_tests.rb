# frozen_string_literal: true
require_relative './environment.rb'

describe 'email recovery' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def issue_recovery_link(email=@new_email)
    visit "/admin/site/#{@site.username}"
    within(:css, 'form[action="/admin/site/email_recovery"]') do
      fill_in 'email_recovery_email', with: email
      click_button 'Send Recovery Link'
    end

    email_job = EmailWorker.jobs.reverse.find do |job|
      job['args'].first['subject'] == '[Neocities] Recover your account email'
    end
    return nil unless email_job

    email_job['args'].first['body'][%r{https://neocities\.org/email_recovery/([A-Za-z0-9_-]+)}, 1]
  end

  def submit_recovery(old_email: @old_email, password: @password)
    fill_in 'Current email address', with: old_email
    fill_in 'Current password', with: password
    click_button 'Change Email Address'
  end

  before do
    Capybara.reset_sessions!
    EmailWorker.jobs.clear
    keys = $redis_cache.keys 'non_signin_password_auth:*'
    $redis_cache.del(*keys) unless keys.empty?

    @admin = Fabricate :site, is_admin: true
    @old_email = "#{SecureRandom.hex}@example.com"
    @new_email = "#{SecureRandom.hex}@example.net"
    @password = SecureRandom.hex
    @site = Fabricate :site, email: @old_email, password: @password
    page.set_rack_session id: @admin.id
  end

  it 'changes the email after verifying the old email and password' do
    @site.update password_reset_token: 'reset-token', password_reset_confirmed: true
    token = issue_recovery_link

    recovery_email = EmailWorker.jobs.find do |job|
      job['args'].first['subject'] == '[Neocities] Recover your account email'
    end['args'].first
    _(recovery_email['to']).must_equal @new_email
    _(token).wont_be_nil

    request_notification = EmailWorker.jobs.find do |job|
      job['args'].first['subject'] == '[Neocities] Email recovery requested'
    end['args'].first
    _(request_notification['to']).must_equal @old_email
    _(request_notification['body']).wont_match Regexp.new(Regexp.escape(@new_email))
    _(request_notification['body']).wont_match %r{/email_recovery/}

    Capybara.reset_sessions!
    visit "/email_recovery/#{token}"
    _(page.response_headers['Cache-Control']).must_include 'no-store'
    _(page.response_headers['Referrer-Policy']).must_equal 'no-referrer'
    submit_recovery old_email: @old_email.upcase

    _(page.current_path).must_equal '/signin'
    _(page).must_have_content 'Your email address has been changed'
    _(page.get_rack_session['id']).must_be_nil

    @site.reload
    _(@site.email).must_equal @new_email
    _(@site.email_confirmed).must_equal true
    _(@site.email_confirmation_token).must_be_nil
    _(@site.password_reset_token).must_be_nil
    _(@site.password_reset_confirmed).must_equal false
    _(@site.email_recovery_email).must_be_nil
    _(@site.email_recovery_token_digest).must_be_nil
    _(@site.email_recovery_expires_at).must_be_nil

    notification = EmailWorker.jobs.find do |job|
      job['args'].first['subject'] == '[Neocities] Your email address has been changed'
    end['args'].first
    _(notification['to']).must_equal @old_email
    _(notification['body']).wont_match Regexp.new(Regexp.escape(@new_email))
    _(notification['body']).wont_match %r{/email_recovery/}
  end

  it 'allows an admin to cancel a pending recovery request' do
    token = issue_recovery_link

    within(:css, 'form[action="/admin/site/email_recovery/cancel"]') do
      click_button 'Cancel Pending Recovery'
    end

    _(page).must_have_content 'Email recovery request canceled.'
    @site.reload
    _(@site.email_recovery_email).must_be_nil
    _(@site.email_recovery_token_digest).must_be_nil
    _(@site.email_recovery_expires_at).must_be_nil

    Capybara.reset_sessions!
    visit "/email_recovery/#{token}"
    _(page.current_path).must_equal '/signin'
    _(page).must_have_content 'invalid or has expired'
  end

  it 'invalidates pending recovery when the email changes normally' do
    token = issue_recovery_link
    changed_email = "#{SecureRandom.hex}@example.org"
    Capybara.reset_sessions!
    page.set_rack_session id: @site.id
    visit '/settings'
    csrf = find('form[action="/settings/change_email"] input[name="csrf_token"]', visible: false).value

    page.driver.post '/settings/change_email', {
      email: changed_email,
      csrf_token: csrf
    }

    @site.reload
    _(@site.email).must_equal changed_email
    _(@site.email_recovery_email).must_be_nil
    _(@site.email_recovery_token_digest).must_be_nil
    _(@site.email_recovery_expires_at).must_be_nil

    Capybara.reset_sessions!
    visit "/email_recovery/#{token}"
    _(page.current_path).must_equal '/signin'
    _(page).must_have_content 'invalid or has expired'
  end

  it 'requires the stored old email address' do
    token = issue_recovery_link
    Capybara.reset_sessions!
    visit "/email_recovery/#{token}"
    submit_recovery old_email: 'not-the-old-address@example.com'

    _(page).must_have_content 'current email address or password was incorrect'
    _(@site.reload.email).must_equal @old_email
    _(@site.email_recovery_token_digest).wont_be_nil
    _(page.get_rack_session['id']).must_be_nil
  end

  it 'requires the current password' do
    token = issue_recovery_link
    Capybara.reset_sessions!
    visit "/email_recovery/#{token}"
    submit_recovery password: 'incorrect-password'

    _(page).must_have_content 'current email address or password was incorrect'
    _(@site.reload.email).must_equal @old_email
    _(@site.email_recovery_token_digest).wont_be_nil
  end

  it 'does not consume the recovery link on get' do
    token = issue_recovery_link
    digest = @site.reload.email_recovery_token_digest
    Capybara.reset_sessions!

    2.times do
      visit "/email_recovery/#{token}"
      _(page).must_have_content 'Recover Your Account Email'
      _(@site.reload.email_recovery_token_digest).must_equal digest
    end
  end

  it 'rejects expired and consumed recovery links' do
    expired_token = issue_recovery_link
    @site.email_recovery_expires_at = 1.second.ago
    @site.save_changes validate: false

    Capybara.reset_sessions!
    visit "/email_recovery/#{expired_token}"
    _(page.current_path).must_equal '/signin'
    _(page).must_have_content 'invalid or has expired'

    page.set_rack_session id: @admin.id
    valid_token = issue_recovery_link
    Capybara.reset_sessions!
    visit "/email_recovery/#{valid_token}"
    submit_recovery
    visit "/email_recovery/#{valid_token}"
    _(page.current_path).must_equal '/signin'
    _(page).must_have_content 'invalid or has expired'
  end

  it 'rejects a new email that is already in use' do
    existing = Fabricate :site
    token = issue_recovery_link existing.email

    _(token).must_be_nil
    _(page).must_have_content 'email address already exists'
    _(@site.reload.email_recovery_token_digest).must_be_nil
    _(EmailWorker.jobs).must_be_empty
  end

  it 'does not issue recovery links for child or banned sites' do
    child = Fabricate :site, parent_site_id: @site.id
    banned = Fabricate :site, is_banned: true
    visit "/admin/site/#{@site.username}"
    csrf = find('form[action="/admin/site/email_recovery"] input[name="csrf_token"]', visible: false).value

    [child, banned].each do |site|
      page.driver.post '/admin/site/email_recovery', {
        username: site.username,
        email: "#{SecureRandom.hex}@example.net",
        csrf_token: csrf
      }
      _(site.reload.email_recovery_token_digest).must_be_nil
    end
  end

  it 'requires csrf when completing recovery' do
    token = issue_recovery_link
    Capybara.reset_sessions!
    page.driver.post "/email_recovery/#{token}", {
      old_email: @old_email,
      password: @password
    }

    _(@site.reload.email).must_equal @old_email
    _(@site.email_recovery_token_digest).wont_be_nil
  end
end
