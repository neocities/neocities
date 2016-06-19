class LetsEncryptWorker
  class NotAuthorizedYetError < StandardError; end
  class VerificationTimeoutError < StandardError; end
  include Sidekiq::Worker
  sidekiq_options queue: :lets_encrypt_worker, retry: 100, backtrace: true

  sidekiq_retry_in do |count|
    180
  end

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

    domains = [site.domain, "www.#{site.domain}"]

    domains.each_with_index do |domain, index|
      auth = letsencrypt.authorize domain: domain
      challenge = auth.http01

      FileUtils.mkdir_p File.join(site.base_files_path, File.dirname(challenge.filename)) if index == 0
      File.write File.join(site.base_files_path, challenge.filename), challenge.file_content

      challenge.request_verification

      sleep 1
      attempts = 0

      begin
        puts "WAITING FOR #{domain} VALIDATION"
        raise VerificationTimeoutError if attempts == 30
        raise NotAuthorizedYetError if challenge.verify_status != 'valid'
      rescue NotAuthorizedYetError
        sleep 5
        attempts += 1
        retry
      end

      puts "DONE!"
    end

    csr = Acme::Client::CertificateRequest.new names: domains
    certificate = letsencrypt.new_certificate csr
    site.ssl_key = certificate.request.private_key.to_pem
    site.ssl_cert = certificate.fullchain_to_pem
    site.save_changes validate: false
    FileUtils.rm_rf File.join(site.base_files_path, '.well-known')
  end
end
