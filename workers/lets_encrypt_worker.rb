class LetsEncryptWorker
  class NotAuthorizedYetError < StandardError; end
  class VerificationTimeoutError < StandardError; end
  include Sidekiq::Worker
  sidekiq_options queue: :lets_encrypt_worker, retry: 100, backtrace: true

  sidekiq_retry_in do |count|
    180
  end

  def perform(site_id)
    letsencrypt = Acme::Client.new(
      private_key: OpenSSL::PKey::RSA.new(File.read($config['letsencrypt_key'])),
      endpoint: $config['letsencrypt_endpoint']
    )

    site = Site[site_id]

    return if site.domain.blank? || site.is_deleted || site.is_banned

    auth = letsencrypt.authorize domain: site.domain

    challenge = auth.http01

    FileUtils.mkdir_p File.join(site.base_files_path, File.dirname(challenge.filename))
    File.write File.join(site.base_files_path, challenge.filename), challenge.file_content

    challenge.request_verification

    sleep 1

    attempts = 0

    begin
      raise VerificationTimeoutError if attempts == 5
      raise NotAuthorizedYet if challenge.verify_status != 'valid'
    rescue NotAuthorizedYet
      sleep 5
      attempts += 1
      retry
    end

    csr = Acme::Client::CertificateRequest.new names: [site.domain, "www.#{site.domain}"]
    certificate = letsencrypt.new_certificate csr
    site.ssl_key = certificate.request.private_key.to_pem
    site.ssl_cert = certificate.fullchain_to_pem
    site.save_changes validate: false
    FileUtils.rm_rf File.join(site.base_files_path, '.well-known')
  end
end
