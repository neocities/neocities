# frozen_string_literal: true
require_relative '../environment.rb'

describe 'site transfers' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  before do
    Capybara.reset_sessions!
    @owner = Fabricate :site, password: 'sender-password'
    @site = Fabricate :site, parent_site_id: @owner.id
    @recipient = Fabricate :site, plan_type: 'supporter', password: 'recipient-password'
    sign_in_as @owner
    visit "/settings/#{@site.username}#transfer"
  end

  def sign_in_as(site)
    Capybara.reset_sessions!
    page.set_rack_session id: site.id, session_version: site.reload.session_version
  end

  def csrf
    first('input[name="csrf_token"]', visible: :all).value
  end

  def create_transfer
    fill_in 'Receiving parent site', with: " #{@recipient.username.upcase} "
    click_button 'Create transfer link'
    URI.parse(find('#transfer_link', visible: :all).value).request_uri
  end

  it 'transfers a child only after the recipient signs in and accepts' do
    @site.update domain: "#{@site.username}.example.com"
    @site.generate_api_key!
    original_files = @site.site_files_dataset.select_map(:path)
    original_content = File.binread @site.files_path('index.html')
    link = create_transfer
    _(@site.reload.parent_site_id).must_equal @owner.id

    Capybara.reset_sessions!
    visit link
    _(page.current_path).must_equal '/signin'
    fill_in 'username', with: @recipient.username
    fill_in 'password', with: 'recipient-password'
    click_button 'Sign In'
    code = EmailWorker.jobs.last['args'].first['body'].match(/verification code is:\s*(\d{6})/i)[1]
    fill_in 'Verification code', with: code
    click_button 'Verify Sign In'
    _(page.current_path).must_equal link
    _(@site.reload.parent_site_id).must_equal @owner.id
    click_button 'Accept transfer'
    token = csrf

    _(@site.reload.parent_site_id).must_equal @recipient.id
    _(@site.api_key).must_be_nil
    _(@site.valid_password?('sender-password')).must_equal false
    _(@site.valid_password?('abcde')).must_equal false
    _(@site.valid_password?('recipient-password')).must_equal true
    _(@site.domain).must_equal "#{@site.username}.example.com"
    _(@site.site_files_dataset.select_map(:path)).must_equal original_files
    _(File.binread(@site.files_path('index.html'))).must_equal original_content
    _($redis_proxy.hget("u-#{@site.username}", 'is_supporter')).must_equal '1'
    _(page.get_rack_session['id']).must_equal @recipient.id

    page.driver.post link, csrf_token: token
    _(page.driver.status_code).must_equal 404
    _(@site.reload.session_version).must_equal 1

    page.set_rack_session id: @site.id, session_version: 0
    visit '/settings'
    _(page.get_rack_session['id']).must_be_nil
    sign_in_as @owner
    settings_url = "#{Capybara.default_host}/settings/#{@site.username}"
    page.driver.header 'Referer', settings_url
    visit "#{settings_url}#transfer"
    _(page.current_path).must_equal '/settings'
    _(page.get_rack_session['id']).must_equal @owner.id
    _(@site.owned_by?(@owner)).must_equal false
  end

  it 'transfers a standalone free site and clears its recovery credentials' do
    @site = Fabricate :site,
      password_reset_token: 'old-reset-token', password_reset_confirmed: true,
      email_recovery_email: 'old@example.com', email_recovery_token_digest: SecureRandom.hex,
      email_recovery_expires_at: Time.now + 1.hour
    sign_in_as @site
    visit "/settings/#{@site.username}#transfer"
    link = create_transfer
    sign_in_as @recipient
    visit link
    click_button 'Accept transfer'

    _(@site.reload.parent_site_id).must_equal @recipient.id
    [:email, :password, :email_confirmation_token, :password_reset_token,
      :email_recovery_email, :email_recovery_token_digest, :email_recovery_expires_at].each do |field|
      _(@site[field]).must_be_nil
    end
    _(@site.password_reset_confirmed).must_equal false
  end

  it 'restricts creating and canceling links to the owner and accepting to the recipient' do
    link = create_transfer
    request = $redis_cache.get "site_transfer:#{@site.id}"
    other = Fabricate :site, plan_type: 'supporter'
    sign_in_as other
    visit '/settings'
    token = csrf

    [{recipient: other.username}, {cancel: 'true'}].each do |params|
      page.driver.post "/settings/#{@site.username}/transfer", params.merge(csrf_token: token)
      _($redis_cache.get("site_transfer:#{@site.id}")).must_equal request
    end
    visit link
    _(page.status_code).must_equal 403
    page.driver.post link, csrf_token: token
    _(page.driver.status_code).must_equal 403
    _(@site.reload.parent_site_id).must_equal @owner.id
  end

  it 'replaces and cancels pending links' do
    old_link = create_transfer
    _(page).wont_have_field 'Receiving parent site'
    page.driver.post "/settings/#{@site.username}/transfer", recipient: @recipient.username, csrf_token: csrf
    visit "/settings/#{@site.username}#transfer"
    new_link = URI.parse(find('#transfer_link', visible: :all).value).request_uri
    sign_in_as @recipient
    visit old_link
    _(page.status_code).must_equal 404

    sign_in_as @owner
    visit "/settings/#{@site.username}#transfer"
    click_button 'Cancel transfer'
    _(page).must_have_field 'Receiving parent site'
    sign_in_as @recipient
    visit new_link
    _(page.status_code).must_equal 404
    _(@site.reload.parent_site_id).must_equal @owner.id
  end

  it 'rejects tampered and expired links' do
    link = create_transfer
    sign_in_as @recipient
    visit "#{link}00"
    _(page.status_code).must_equal 404
    _($redis_cache.ttl("site_transfer:#{@site.id}")).must_be :<=, 24.hours.to_i
    $redis_cache.expire "site_transfer:#{@site.id}", 0
    visit link
    _(page.status_code).must_equal 404
    _(@site.reload.parent_site_id).must_equal @owner.id
  end

  it 'rejects invalid receiving accounts' do
    recipients = [@owner, Fabricate(:site),
      Fabricate(:site, parent_site_id: @recipient.id),
      Fabricate(:site, plan_type: 'supporter', is_banned: true),
      Fabricate(:site, plan_type: 'supporter', is_deleted: true)]
    names = recipients.map(&:username) + ['missing-site']
    token = csrf

    names.each do |name|
      page.driver.post "/settings/#{@site.username}/transfer", recipient: name, csrf_token: token
      _($redis_cache.get("site_transfer:#{@site.id}")).must_be_nil
    end
    _(@site.reload.parent_site_id).must_equal @owner.id
  end

  it 'rechecks site and recipient eligibility before accepting' do
    link = create_transfer
    sign_in_as @recipient
    visit link
    token = csrf
    cases = [[@site, {is_banned: true}], [@site, {is_deleted: true}],
      [@site, {is_admin: true}], [@site, {plan_type: 'supporter'}],
      [@site, {stripe_subscription_id: 'sub_existing'}], [@site, {paypal_active: true}],
      [@owner, {is_banned: true}], [@recipient, {plan_type: 'free'}],
      [@recipient, {space_used: @recipient.maximum_space}]]

    cases.each do |site, changes|
      original = site.values.slice(*changes.keys)
      site.update changes
      page.driver.post link, csrf_token: token
      _(page.driver.status_code).must_equal 403
      _(@site.reload.parent_site_id).must_equal @owner.id
      site.update original
    end

    child = Fabricate :site, parent_site_id: @site.id
    page.driver.post link, csrf_token: token
    _(page.driver.status_code).must_equal 403
    child.update parent_site_id: @recipient.id
    (Site::CHILD_SITES_MAX - @recipient.account_sites_dataset.count).times do
      Fabricate :site, parent_site_id: @recipient.id
    end
    page.driver.post link, csrf_token: token
    _(page.driver.status_code).must_equal 403
    _(@site.reload.parent_site_id).must_equal @owner.id
  end

  it 'requires CSRF tokens to create, cancel, and accept transfers' do
    page.driver.post "/settings/#{@site.username}/transfer", recipient: @recipient.username
    _($redis_cache.get("site_transfer:#{@site.id}")).must_be_nil
    visit "/settings/#{@site.username}#transfer"
    link = create_transfer
    page.driver.post "/settings/#{@site.username}/transfer", cancel: 'true'
    _($redis_cache.get("site_transfer:#{@site.id}")).wont_be_nil
    sign_in_as @recipient
    visit link
    page.driver.post link
    _(@site.reload.parent_site_id).must_equal @owner.id
  end
end
