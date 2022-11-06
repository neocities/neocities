require_relative '../environment.rb'

def generate_ssl_certs(opts={})
  # https://github.com/kyledrake/ruby-openssl-cheat-sheet/blob/master/certificate_authority.rb
  res = {}

  ca_keypair = OpenSSL::PKey::RSA.new(2048)
  ca_cert = OpenSSL::X509::Certificate.new
  ca_cert.not_before = Time.now
  ca_cert.subject = OpenSSL::X509::Name.new([
    ["C", "US"],
    ["ST", "Oregon"],
    ["L", "Portland"],
    ["CN", "Neocities CA"]
  ])
  ca_cert.issuer = ca_cert.subject
  ca_cert.not_after = Time.now + 1000000000 # 40 or so years
  ca_cert.serial = 1
  ca_cert.public_key = ca_keypair.public_key
  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = ca_cert
  ef.issuer_certificate = ca_cert
  # Read more about the various extensions here: http://www.openssl.org/docs/apps/x509v3_config.html
  ca_cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
  ca_cert.add_extension(ef.create_extension("keyUsage","keyCertSign, cRLSign", true))
  ca_cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash", false))
  ca_cert.add_extension(ef.create_extension("authorityKeyIdentifier", "keyid:always", false))
  ca_cert.sign(ca_keypair, OpenSSL::Digest::SHA256.new)
  res[:ca_cert] = ca_cert
  res[:ca_keypair] = ca_keypair

  ca_cert = OpenSSL::X509::Certificate.new(res[:ca_cert].to_pem)
  our_cert_keypair = OpenSSL::PKey::RSA.new(2048)
  our_cert_req = OpenSSL::X509::Request.new
  our_cert_req.subject = OpenSSL::X509::Name.new([
  ["C", "US"],
  ["ST", "Oregon"],
  ["L", "Portland"],
  ["O", "Neocities User"],
  ["CN", "*.#{opts[:domain]}"]
  ])
  our_cert_req.public_key = our_cert_keypair.public_key
  our_cert_req.sign our_cert_keypair, OpenSSL::Digest::SHA1.new
  our_cert = OpenSSL::X509::Certificate.new
  our_cert.subject = our_cert_req.subject
  our_cert.issuer = ca_cert.subject
  our_cert.not_before = Time.now
  if opts[:expired]
    our_cert.not_after = Time.now - 100000000
  else
    our_cert.not_after = Time.now + 100000000
  end
  our_cert.serial = 123 # Should be an unique number, the CA probably has a database.
  our_cert.public_key = our_cert_req.public_key
  # To make the certificate valid for both wildcard and top level domain name, we need an extension.
  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = our_cert
  ef.issuer_certificate = ca_cert
  our_cert.add_extension(ef.create_extension("subjectAltName", "DNS:#{@domain}, DNS:*.#{@domain}", false))
  our_cert.sign res[:ca_keypair], OpenSSL::Digest::SHA1.new

  our_cert_tmpfile = Tempfile.new 'our_cert'
  our_cert_tmpfile.write our_cert.to_pem
  our_cert_tmpfile.close
  res[:cert_path] = our_cert_tmpfile.path

  res[:key_path] = '/tmp/nc_test_our_cert_keypair'
  File.write res[:key_path], our_cert_keypair.to_pem

  res[:cert_intermediate_path] = '/tmp/nc_test_ca_cert'
  File.write res[:cert_intermediate_path], res[:ca_cert].to_pem

  res[:combined_cert_path] = '/tmp/nc_test_combined_cert'
  File.write res[:combined_cert_path], "#{File.read(res[:cert_path])}\n#{File.read(res[:cert_intermediate_path])}"

  res[:bad_combined_cert_path] = '/tmp/nc_test_bad_combined_cert'
  File.write res[:bad_combined_cert_path], "#{File.read(res[:cert_intermediate_path])}\n#{File.read(res[:cert_path])}"

  res
end

describe 'site/settings' do
  describe 'permissions' do
    include Capybara::DSL

    before do
      @parent_site = Fabricate :site
      @child_site = Fabricate :site, parent_site_id: @parent_site.id
      @other_site = Fabricate :site
    end

    it 'fails without permissions' do
      page.set_rack_session id: @other_site.id

      visit "/settings/#{@parent_site.username}"
      _(page.current_path).must_equal '/' # This could be better
    end

    it 'allows child site editing from parent' do
      page.set_rack_session id: @parent_site.id
      visit "/settings/#{@child_site.username}"
      _(page.current_path).must_equal "/settings/#{@child_site.username}"
    end
  end

  describe 'changing username' do
    include Capybara::DSL

    before do
      Capybara.reset_sessions!
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit "/settings/#{@site[:username]}#username"
    end

    after do
      _(Site[username: @site[:username]]).wont_equal nil
    end

    it 'fails for blank username' do
      fill_in 'name', with: ''
      click_button 'Change Name'
      _(page).must_have_content /cannot be blank/i
      _(Site[username: '']).must_be_nil
    end

    it 'fails for subdir periods' do
      fill_in 'name', with: '../hack'
      click_button 'Change Name'
      _(page).must_have_content /Usernames can only contain/i
      _(Site[username: '../hack']).must_be_nil
    end

    it 'fails for same username' do
      fill_in 'name', with: @site.username
      click_button 'Change Name'
      _(page).must_have_content /You already have this name/
    end

    it 'fails for same username with DiFfErEnT CaSiNg' do
      fill_in 'name', with: @site.username.upcase
      click_button 'Change Name'
      _(page).must_have_content /You already have this name/
    end
  end
end

describe 'delete' do
  include Capybara::DSL

  before do
    Capybara.reset_sessions!
    @site = Fabricate :site
    page.set_rack_session id: @site.id
    visit "/settings/#{@site[:username]}#delete"
  end

  it 'fails for incorrect entered username' do
    fill_in 'username', with: 'NOPE'
    click_button 'Delete Site'

    _(page.body).must_match /Site user name and entered user name did not match/i
    _(@site.reload.is_deleted).must_equal false
  end

  it 'succeeds' do
    deleted_reason = 'Penelope left a hairball on my site'

    fill_in 'confirm_username', with: @site.username
    fill_in 'deleted_reason', with: deleted_reason
    click_button 'Delete Site'

    @site.reload
    _(@site.is_deleted).must_equal true
    _(@site.deleted_reason).must_equal deleted_reason
    _(page.current_path).must_equal '/'

    _(File.exist?(@site.files_path('./index.html'))).must_equal false
    _(Dir.exist?(@site.files_path)).must_equal false

    path = File.join Site::DELETED_SITES_ROOT, Site.sharding_dir(@site.username), @site.username
    _(Dir.exist?(path)).must_equal true
    _(File.exist?(File.join(path, 'index.html'))).must_equal true

    visit "/site/#{@site.username}"
    _(page.status_code).must_equal 404
  end

  it 'stops charging for supporter account' do
    customer = Stripe::Customer.create(
      source: $stripe_helper.generate_card_token
    )

    subscription = customer.subscriptions.create plan: 'supporter'

    @site.update(
      stripe_customer_id: customer.id,
      stripe_subscription_id: subscription.id,
      plan_type: 'supporter'
    )

    @site.plan_type = subscription.plan.id
    @site.save_changes

    fill_in 'confirm_username', with: @site.username
    fill_in 'deleted_reason', with: 'derp'
    click_button 'Delete Site'

    _(Stripe::Customer.retrieve(@site.stripe_customer_id).subscriptions.count).must_equal 0
    @site.reload
    _(@site.stripe_subscription_id).must_be_nil
    _(@site.is_deleted).must_equal true
  end

  it 'should fail unless owned by current user' do
    someone_elses_site = Fabricate :site
    page.set_rack_session id: @site.id

    page.driver.post "/settings/#{someone_elses_site.username}/delete", {
      username: someone_elses_site.username,
      deleted_reason: 'Dade Murphy enters Acid Burns turf'
    }

    _(page.driver.status_code).must_equal 302
    _(URI.parse(page.driver.response_headers['Location']).path).must_equal '/'
    someone_elses_site.reload
    _(someone_elses_site.is_deleted).must_equal false
  end

  it 'should not show NSFW tab for admin NSFW flag' do
    owned_site = Fabricate :site, parent_site_id: @site.id, admin_nsfw: true
    visit "/settings/#{owned_site.username}"
    _(page.body).wont_match /18\+/
  end

  it 'should succeed if you own the site' do
    owned_site = Fabricate :site, parent_site_id: @site.id
    visit "/settings/#{owned_site.username}#delete"
    fill_in 'confirm_username', with: owned_site.username
    click_button 'Delete Site'

    @site.reload
    owned_site.reload
    _(owned_site.is_deleted).must_equal true
    _(@site.is_deleted).must_equal false

    _(page.current_path).must_equal "/settings"
  end

  it 'fails to delete parent site if children exist' do
    owned_site = Fabricate :site, parent_site_id: @site.id
    visit "/settings/#{@site.username}#delete"
    _(page.body).must_match /You cannot delete the parent site without deleting the children sites first/i
  end
end
