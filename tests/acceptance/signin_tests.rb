# frozen_string_literal: true
require_relative './environment.rb'

describe 'signin' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  def fill_in_valid
    @site = Fabricate.attributes_for :site
    fill_in 'username', with: @site[:username]
    fill_in 'password', with: @site[:password]
  end

  def verification_code
    email = EmailWorker.jobs.last['args'].first
    email['body'].match(/verification code is:\s*(\d{6})/i)[1]
  end

  def incorrect_verification_code
    verification_code == '000000' ? '111111' : '000000'
  end

  def complete_email_verification(code=verification_code)
    fill_in 'Verification code', with: code
    click_button 'Verify Sign In'
  end

  def clear_email_login_redis
    keys = $redis_cache.keys 'email_login:*'
    $redis_cache.del(*keys) unless keys.empty?
  end

  before do
    Capybara.reset_sessions!
    EmailWorker.jobs.clear
    clear_email_login_redis
  end

  it 'restores a deleted site' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    @site.destroy
    _(Dir.exist?(@site.files_path)).must_equal false
    _(Dir.exist?(@site.deleted_files_path)).must_equal true
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Restore Site'
    click_button 'Restore Site'
    _(@site.reload.is_deleted).must_equal true
    _(Dir.exist?(@site.deleted_files_path)).must_equal true
    _(page).must_have_content 'Verify Your Sign In'
    complete_email_verification
    _(Dir.exist?(@site.deleted_files_path)).must_equal false
    _(Dir.exist?(@site.files_path)).must_equal true
    _(@site.reload.is_deleted).must_equal false
  end

  it 'fails for invalid signin' do
    visit '/'
    click_link 'Sign In'
    _(page).must_have_content 'Welcome Back'
    fill_in_valid
    click_button 'Sign In'
    _(page).must_have_content 'Invalid login'
  end

  it 'fails for missing signin' do
    visit '/'
    click_link 'Sign In'
    auth = {username: SecureRandom.hex, password: Faker::Internet.password}
    fill_in 'username', with: auth[:username]
    fill_in 'password', with: auth[:password]
    click_button 'Sign In'
    _(page).must_have_content 'Invalid login'
  end

  it 'requires a captcha after two failed signin attempts' do
    pass = SecureRandom.hex
    site = Fabricate :site, password: pass
    visit '/signin'

    2.times do |attempt|
      fill_in 'username', with: site.username
      fill_in 'password', with: 'incorrect password'
      click_button 'Sign In'
      _(page).must_have_content 'Invalid login'
      _(page).wont_have_content 'Fill out the captcha' if attempt.zero?
    end

    _(page).must_have_content 'Fill out the captcha'
    fill_in 'username', with: site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Please complete the captcha'
    _(EmailWorker.jobs).must_be_empty

    csrf = find('input[name="csrf_token"]', visible: false).value
    page.driver.submit :post, '/signin', {
      csrf_token: csrf,
      username: site.username,
      password: pass,
      'h-captcha-response': 'test-response'
    }

    _(page).must_have_content 'Verify Your Sign In'
    _(page.get_rack_session['signin_attempts']).must_be_nil
  end

  it 'signs in with proper credentials' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    _(page).must_have_content 'Verify Your Sign In'
    complete_email_verification
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with invalid case username' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.username.upcase
    fill_in 'password', with: pass
    click_button 'Sign In'
    complete_email_verification
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with email' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.email
    fill_in 'password', with: pass
    click_button 'Sign In'
    complete_email_verification
    _(page).must_have_content 'Your Feed'
  end

  it 'signs in with invalid case email' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/'
    click_link 'Sign In'
    fill_in 'username', with: @site.email.upcase
    fill_in 'password', with: pass
    click_button 'Sign In'
    complete_email_verification
    _(page).must_have_content 'Your Feed'
  end

  it 'sends child site verification codes to the owner email' do
    pass = SecureRandom.hex
    owner = Fabricate :site, password: pass
    child = Fabricate :site, parent_site_id: owner.id, email: nil
    visit '/signin'
    fill_in 'username', with: child.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    email = EmailWorker.jobs.last['args'].first
    _(email['to']).must_equal owner.email
    _(email['no_footer']).must_equal true
    complete_email_verification

    _(page).must_have_content 'Your Feed'
    _(page.get_rack_session['id']).must_equal child.id
  end

  it 'does not sign in with an incorrect verification code' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    fill_in 'Verification code', with: incorrect_verification_code
    click_button 'Verify Sign In'

    _(page).must_have_content 'Invalid verification code'
    visit '/dashboard'
    _(URI.parse(page.current_url).path).must_equal '/'
  end

  it 'expires a verification code after ten minutes' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    Timecop.freeze(Time.now+EMAIL_LOGIN_CODE_TTL+1) do
      visit '/signin/verify'
      _(page).must_have_content 'verification code has expired'
      _(URI.parse(page.current_url).path).must_equal '/signin'
    end
  end

  it 'requires a new login after five incorrect codes' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    incorrect_code = incorrect_verification_code
    EMAIL_LOGIN_MAX_ATTEMPTS.times do
      fill_in 'Verification code', with: incorrect_code
      click_button 'Verify Sign In'
    end

    _(page).must_have_content 'Too many incorrect verification codes'
    _(URI.parse(page.current_url).path).must_equal '/signin'
  end

  it 'enforces the attempt limit when an old session cookie is restored' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    pending_session = page.get_rack_session.to_h
    correct_code = verification_code
    incorrect_code = incorrect_verification_code

    EMAIL_LOGIN_MAX_ATTEMPTS.times do
      page.set_rack_session pending_session
      visit '/signin/verify'
      complete_email_verification incorrect_code
    end

    page.set_rack_session pending_session
    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
    _(page).wont_have_content correct_code
  end

  it 'does not allow a consumed challenge to be replayed' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    pending_session = page.get_rack_session.to_h
    visit '/signin/verify'
    complete_email_verification
    _(page).must_have_content 'Your Feed'

    Capybara.reset_sessions!
    page.set_rack_session pending_session
    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
  end

  it 'keeps the attempts key expiring after a challenge is consumed' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    challenge_id = page.get_rack_session['email_login_challenge_id']
    visit '/signin/verify'
    complete_email_verification

    attempts_key = email_login_attempts_key challenge_id
    $redis_cache.incr attempts_key
    ttl = $redis_cache.ttl attempts_key
    _(ttl).must_be :>, 0
    _(ttl).must_be :<=, EMAIL_LOGIN_CODE_TTL
  end

  it 'invalidates a pending challenge when sign in is cancelled' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    pending_session = page.get_rack_session.to_h
    challenge_id = pending_session['email_login_challenge_id']
    visit '/signin/verify'
    click_button 'Cancel and sign in again'

    _(URI.parse(page.current_url).path).must_equal '/signin'
    _(page.get_rack_session['email_login_challenge_id']).must_be_nil
    _($redis_cache.get(email_login_challenge_key(challenge_id))).must_be_nil
    _($redis_cache.get(email_login_attempts_key(challenge_id))).must_be_nil

    page.set_rack_session pending_session
    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
  end

  it 'invalidates an older challenge when issuing a new one' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'
    old_session = page.get_rack_session.to_h

    rate_keys = $redis_cache.keys 'email_login:rate:*'
    $redis_cache.del(*rate_keys) unless rate_keys.empty?
    Capybara.reset_sessions!
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    page.set_rack_session old_session
    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
  end

  it 'invalidates a challenge when the password changes' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    @site.password = SecureRandom.hex
    @site.save_changes

    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
  end

  it 'invalidates a challenge when the email changes' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    @site.email = "changed-#{@site.email}"
    @site.save_changes

    visit '/signin/verify'
    _(page).must_have_content 'verification code has expired'
  end

  it 'rate limits verification emails by IP' do
    EMAIL_LOGIN_IP_LIMIT.times do
      _(email_login_under_rate_limit?(:ip, '192.0.2.1', EMAIL_LOGIN_IP_LIMIT)).must_equal true
    end
    _(email_login_under_rate_limit?(:ip, '192.0.2.1', EMAIL_LOGIN_IP_LIMIT)).must_equal false
  end

  it 'rate limits verification emails by account' do
    pass = SecureRandom.hex
    @site = Fabricate :site, password: pass
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    Capybara.reset_sessions!
    visit '/signin'
    fill_in 'username', with: @site.username
    fill_in 'password', with: pass
    click_button 'Sign In'

    _(page).must_have_content 'Please wait before requesting another sign in verification code'
    _(EmailWorker.jobs.length).must_equal 1
  end
end
