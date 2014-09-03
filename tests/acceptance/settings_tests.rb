require_relative './environment.rb'

describe 'site/settings' do
  describe 'ssl' do
    include Capybara::DSL

    before do
      # https://github.com/kyledrake/ruby-openssl-cheat-sheet/blob/master/certificate_authority.rb
      # TODO make ca generation run only once
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
      # All issued certs will be unusuable after this time.
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
      @ca_cert = ca_cert
      @ca_keypair = ca_keypair

      @domain = SecureRandom.uuid.gsub('-', '')+'.com'
      @site = Fabricate :site, domain: @domain
      page.set_rack_session id: @site.id

      ca_cert = OpenSSL::X509::Certificate.new(@ca_cert.to_pem)
      our_cert_keypair = OpenSSL::PKey::RSA.new(2048)
      our_cert_req = OpenSSL::X509::Request.new
      our_cert_req.subject = OpenSSL::X509::Name.new([
      ["C", "US"],
      ["ST", "Oregon"],
      ["L", "Portland"],
      ["O", "Neocities User"],
      ["CN", "*.#{@domain}"]
      ])
      our_cert_req.public_key = our_cert_keypair.public_key
      our_cert_req.sign our_cert_keypair, OpenSSL::Digest::SHA1.new
      our_cert = OpenSSL::X509::Certificate.new
      our_cert.subject = our_cert_req.subject
      our_cert.issuer = ca_cert.subject
      our_cert.not_before = Time.now
      our_cert.not_after = Time.now + 100000000 # 3 or so years.
      our_cert.serial = 123 # Should be an unique number, the CA probably has a database.
      our_cert.public_key = our_cert_req.public_key
      # To make the certificate valid for both wildcard and top level domain name, we need an extension.
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = our_cert
      ef.issuer_certificate = ca_cert
      our_cert.add_extension(ef.create_extension("subjectAltName", "DNS:#{@domain}, DNS:*.#{@domain}", false))
      our_cert.sign @ca_keypair, OpenSSL::Digest::SHA1.new

      our_cert_tmpfile = Tempfile.new 'our_cert'
      our_cert_tmpfile.write our_cert.to_pem
      our_cert_tmpfile.close
      @cert_path = our_cert_tmpfile.path

      our_cert_keypair_tmpfile = Tempfile.new 'our_cert_keypair'
      our_cert_keypair_tmpfile.write our_cert_keypair.to_pem
      our_cert_keypair_tmpfile.close
      @key_path = our_cert_keypair_tmpfile.path

      ca_cert_tmpfile = Tempfile.new 'ca_cert'
      ca_cert_tmpfile.write @ca_cert.to_pem
      ca_cert_tmpfile.close
      @cert_intermediate_path = ca_cert_tmpfile.path

    end

    it 'fails without domain set' do
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit '/custom_domain'
      page.must_have_content /Cannot upload SSL certificate until domain is added/i
    end

    it 'works with valid key, cert and intermediate cert' do
      visit '/custom_domain'
      page.must_have_content /status: inactive/i
      attach_file 'key', @key_path
      attach_file 'cert', @cert_path
      attach_file 'cert_intermediate', @cert_intermediate_path
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /Updated SSL/
      page.must_have_content /status: installed/i
      @site.reload
      @site.ssl_key.must_equal File.read(@key_path)
      @site.ssl_cert.must_equal File.read(@cert_path)
      @site.ssl_cert_intermediate.must_equal File.read(@cert_intermediate_path)
    end

    it 'fails with no uploads' do
      visit '/custom_domain'
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /ssl key.+certificate.+intermediate.+required to continue/i
      @site.reload
      @site.ssl_key.must_equal nil
      @site.ssl_cert.must_equal nil
      @site.ssl_cert_intermediate.must_equal nil
    end

    it 'fails with encrypted key' do
      visit '/custom_domain'
      attach_file 'key', './tests/files/ssl/derpie.com-encrypted.key'
      attach_file 'cert', @cert_path
      attach_file 'cert_intermediate', @cert_intermediate_path
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl key/i
    end

    it 'fails with junk key' do
      visit '/custom_domain'
      attach_file 'key', './tests/files/index.html'
      attach_file 'cert', @cert_path
      attach_file 'cert_intermediate', @cert_intermediate_path
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl key/i
    end

    it 'fails with junk cert' do
      visit '/custom_domain'
      attach_file 'key', @key_path
      attach_file 'cert', './tests/files/index.html'
      attach_file 'cert_intermediate', @cert_intermediate_path
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process ssl certificate/i
    end

    it 'fails with junk intermediate cert' do
      visit '/custom_domain'
      attach_file 'key', @key_path
      attach_file 'cert', @cert_path
      attach_file 'cert_intermediate', './tests/files/index.html'
      click_button 'Upload SSL Key and Certificate'
      page.current_path.must_equal '/custom_domain'
      page.must_have_content /could not process intermediate ssl certificate/i
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