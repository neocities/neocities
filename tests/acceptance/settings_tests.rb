require_relative './environment.rb'

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

  our_cert_keypair_tmpfile = Tempfile.new 'our_cert_keypair'
  our_cert_keypair_tmpfile.write our_cert_keypair.to_pem
  our_cert_keypair_tmpfile.close
  res[:key_path] = our_cert_keypair_tmpfile.path

  ca_cert_tmpfile = Tempfile.new 'ca_cert'
  ca_cert_tmpfile.write res[:ca_cert].to_pem
  ca_cert_tmpfile.close
  res[:cert_intermediate_path] = ca_cert_tmpfile.path

  combined_cert_tmpfile = Tempfile.new 'combined_cert'
  combined_cert_tmpfile.write "#{File.read(res[:cert_path])}\n#{File.read(res[:cert_intermediate_path])}"
  combined_cert_tmpfile.close
  res[:combined_cert_path] = combined_cert_tmpfile.path

  bad_combined_cert_tmpfile = Tempfile.new 'bad_combined_cert'
  bad_combined_cert_tmpfile.write "#{File.read(res[:cert_intermediate_path])}\n#{File.read(res[:cert_path])}"
  bad_combined_cert_tmpfile.close
  res[:bad_combined_cert_path] = bad_combined_cert_tmpfile.path

  res
end

describe 'site/settings' do
  describe 'ssl' do
    include Capybara::DSL

    before do
      @domain = SecureRandom.uuid.gsub('-', '')+'.com'
      @site = Fabricate :site, domain: @domain
      page.set_rack_session id: @site.id
      
    end

    it 'fails without domain set' do
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit '/custom_domain'
      page.must_have_content /Cannot upload SSL certificate until domain is added/i
    end

    it 'fails with expired key' do
      @ssl = generate_ssl_certs domain: @domain, expired: true
      visit '/custom_domain'
      attach_file 'key', @ssl[:key_path]
      attach_file 'cert', @ssl[:combined_cert_path]
      click_button 'Upload SSL Key and Certificate'
      page.must_have_content /ssl certificate has expired/i
    end

    it 'works with valid key and unified cert' do
      @ssl = generate_ssl_certs domain: @domain
      visit '/custom_domain'
      key = File.read @ssl[:key_path]
      combined_cert = File.read @ssl[:combined_cert_path]
      page.must_have_content /status: inactive/i
      attach_file 'key', @ssl[:key_path]
      attach_file 'cert', @ssl[:combined_cert_path]
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /Updated SSL/
      page.must_have_content /status: installed/i
      @site.reload
      @site.ssl_key.must_equal key
      @site.ssl_cert.must_equal combined_cert
    end

    it 'fails with no uploads' do
      visit '/custom_domain'
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /ssl key.+certificate.+required/i
      @site.reload
      @site.ssl_key.must_equal nil
      @site.ssl_cert.must_equal nil
    end

    it 'fails gracefully with encrypted key' do
      @ssl = generate_ssl_certs domain: @domain
      visit '/custom_domain'
      attach_file 'key', './tests/files/ssl/derpie.com-encrypted.key'
      attach_file 'cert', @ssl[:cert_path]
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl key/i
    end

    it 'fails with junk key' do
      @ssl = generate_ssl_certs domain: @domain
      visit '/custom_domain'
      attach_file 'key', './tests/files/index.html'
      attach_file 'cert', @ssl[:cert_path]
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl key/i
    end

    it 'fails with junk cert' do
      @ssl = generate_ssl_certs domain: @domain
      visit '/custom_domain'
      attach_file 'key', @ssl[:key_path]
      attach_file 'cert', './tests/files/index.html'
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl certificate/i
    end

    if ENV['TRAVIS'] != 'true'
      it 'fails with bad cert chain' do
        @ssl = generate_ssl_certs domain: @domain
        visit '/custom_domain'
        attach_file 'key', @ssl[:key_path]
        attach_file 'cert', @ssl[:bad_combined_cert_path]
        click_button 'Upload SSL Key and Certificate'
        page.current_path.must_equal '/custom_domain'
        page.must_have_content /there is something wrong with your certificate/i
      end
    end
  end

  describe 'change username' do
    include Capybara::DSL

    def visit_signup
      visit '/'
      click_button 'Create My Website'
    end

    def fill_in_valid
      @site = Fabricate.attributes_for(:site)
      fill_in 'username', with: @site[:username]
      fill_in 'password', with: @site[:password]
      fill_in 'email',    with: @site[:email]
    end

    before do
      Capybara.reset_sessions!
      visit_signup
    end

    it 'does not allow bad usernames' do
      visit '/'
      click_button 'Create My Website'
      fill_in_valid
      click_button 'Create Home Page'
      visit '/settings'
      fill_in 'name', with: ''
      click_button 'Change Name'
      fill_in 'name', with: '../hack'
      click_button 'Change Name'
      fill_in 'name', with: 'derp../hack'
      click_button 'Change Name'
      ## TODO fix this without screwing up legacy sites
      #fill_in 'name', with: '-'
      #click_button 'Change Name'
      page.must_have_content /valid.+name.+required/i
      Site[username: @site[:username]].wont_equal nil
      Site[username: ''].must_equal nil
    end
  end
end