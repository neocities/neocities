class CreateSSLCertWorker
  include Sidekiq::Worker
  sidekiq_options queue: :create_ssl_cert_worker, retry: 100, backtrace: true

  sidekiq_retry_in do |count|
    180
  end

  def perform(site_id, challenge)
    site = Site[site_id]

    challenge = $letsencrypt.challenge_from_hash JSON.parse(challenge)
    if challenge.verify_status == 'valid'
      site.obtain_ssl_certificate
    end
  end
end
