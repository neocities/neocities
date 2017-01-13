class LetsEncryptWorker
  class NotAuthorizedYetError < StandardError; end
  class VerificationTimeoutError < StandardError; end
  class InvalidAuthError < StandardError; end
  class VerifyNotFoundWithDomain < StandardError; end
  include Sidekiq::Worker
  sidekiq_options queue: :lets_encrypt_worker, retry: 10, backtrace: true

  sidekiq_retry_in do |count|
    5.minutes.to_i * count
  end

  # If you need to clear scheduled jobs:
  # Sidekiq::ScheduledSet.new.select {|s| JSON.parse(s.value)['class'] == 'LetsEncryptWorker'}.each {|j| j.delete}

  def letsencrypt
    Acme::Client.new(
      private_key: OpenSSL::PKey::RSA.new(File.read($config['letsencrypt_key'])),
      endpoint: $config['letsencrypt_endpoint']
    )
  end

  def perform(site_id)
    # Dispose of dupes
    queue = Sidekiq::Queue.new self.class.sidekiq_options_hash['queue']
    queue.each do |job|
      if job.args == [site_id] && job.jid != jid
        job.delete
      end
    end

    site = Site[site_id]
    return if site.domain.blank? || site.is_deleted || site.is_banned

    return if site.values[:domain].match /\.neocities\.org$/i

    domain_raw = site.values[:domain].gsub(/^www\./, '')

    domains = [domain_raw, "www.#{domain_raw}"]

    verified_domains = []

    domains.each_with_index do |domain, index|
      puts "verifying accessability of test file on #{domain}"
      challenge_base_path = File.join '.well-known', 'acme-challenge'
      testfile_name, testfile_key = "test#{UUIDTools::UUID.random_create}", SecureRandom.hex
      testfile_fs_path = File.join site.base_files_path, challenge_base_path

      begin
        FileUtils.mkdir_p File.join(site.base_files_path, challenge_base_path)
        File.write File.join(testfile_fs_path, testfile_name), testfile_key
      rescue => e
        puts "ERROR WRITING TO WELLKNOWN FILE, FAILING ON THIS SITE: #{site.username} #{domain}: #{e.inspect}"
        return
      end

      # Ensure that both domains work before sending request. Let's Encrypt has a low
      # pending request limit, and it takes one week (!) to flush out.

      challenge_url = "http://#{domain}/#{challenge_base_path}/#{testfile_name}"

      puts "testing #{challenge_url}"

      begin
        res = HTTP.timeout(:global, write: 5, connect: 10, read: 10).follow.get(challenge_url)
      rescue
        puts "error with #{challenge_url}"
        next
      end

      if res.status != 200 && res.body != testfile_key
        puts "CONTENT DOWNLOADED DID NOT MATCH #{challenge_url}"
        next
      end

      puts "test succeeded, sending challenge request verification"

      begin
        auth = letsencrypt.authorize domain: domain
        challenge = auth.http01
      rescue => e
        if e.message =~ /Internationalized domain names.+not yet supported/
          @international_domain = true
          puts "This is an internationalized domain, and so is not yet supported. Skipping to next"
          next
        else
          raise e
        end
      end

      if challenge.nil?
        puts "challenge object is nil, going to next domain"
        next
      end

      begin
        FileUtils.mkdir_p File.join(site.base_files_path, File.dirname(challenge.filename))
        File.write File.join(site.base_files_path, challenge.filename), challenge.file_content
      rescue => e
        puts "FAILED TO WRITE CHALLENGE: #{site.domain} #{challenge.filename}"
        # A verification needs to be attempted anyways, otherwise 300 of them will jam up the system for a week
      end

      challenge.request_verification

      sleep 1
      attempts = 0

      while true
        result = challenge.verify_status
        puts "#{domain} : #{result}"

        if result == 'valid'
          puts "VALIDATED: #{domain}"
          clean_wellknown_turds site
          verified_domains.push domain
          break
        end

        raise VerificationTimeoutError if attempts == 60

        if result == 'invalid'
          puts "returned invalid, walking away"
          clean_wellknown_turds site
          break
        end

        attempts += 1
        sleep 2
      end
    end

    if verified_domains.empty? || (site.created_at >= 2017 && !verified_domains.include?(domain_raw))
      if @international_domain
        puts "still waiting on IDN support, ignoring failure for now"
        clean_wellknown_turds site
        return
      end

      puts "no verified domains, skipping cert setup, reporting invalid domain"

      # This is a bit of an inappropriate shared responsibility,
      # but since were here, it looks like the domain is dead, so let's
      # try again a few times, but then pull the domain out of our system
      # if it looks like it's gone completely.

      if site.domain_fail_count < 60
        site.domain_fail_count += 1
        site.save_changes validate: false
      else
        old_domain = site.domain
        site.domain = nil
        site.domain_fail_count = 0
        site.save validate: false

        site.send_email(
          subject: "[Neocities] Your domain has stopped working",
          body: Tilt.new('./views/templates/email/domain_fail.erb', pretty: true).render(self, site: site, domain: old_domain)
        )
      end

      clean_wellknown_turds site

      if site.domain_fail_count > 0
        LetsEncryptWorker.perform_in((5.minutes * site.domain_fail_count), site.id)
      end
      return
    end

    puts "verified domains: #{verified_domains.inspect}"

    clean_wellknown_turds site

    retries = 0
    begin
      csr = Acme::Client::CertificateRequest.new names: verified_domains
      certificate = letsencrypt.new_certificate csr
    rescue Acme::Client::Error => e
      if retries == 2
        puts "Failed to create cert, returning: #{e.message}"
        return
      end
      retries += 1
      retry
    end

    site.ssl_key = certificate.request.private_key.to_pem
    site.ssl_cert = certificate.fullchain_to_pem
    site.cert_updated_at = Time.now
    site.save_changes validate: false

    # Refresh the cert periodically, current expire time is 90 days
    # We're going for a cron task for this now, so this is commented out.
    #LetsEncryptWorker.perform_in 60.days, site.id
  end

  def clean_wellknown_turds(site)
    wellknown_path = File.join(site.base_files_path, '.well-known')

    if File.exist?(wellknown_path)
      FileUtils.rm_rf wellknown_path
    end
  end
end
