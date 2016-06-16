class RequestSSLAuthWorker
  include Sidekiq::Worker
  sidekiq_options queue: :request_ssl_auth_worker, retry: 100, backtrace: true

  sidekiq_retry_in do |count|
    180
  end

  def perform(site_id)
    site = Site[site_id]
    challenge = site.request_ssl_authorization

    CreateSSLCertWorker.perform_in 5.seconds, site_id, challenge.to_h.to_json
  end
end
