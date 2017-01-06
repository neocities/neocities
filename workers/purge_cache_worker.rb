require 'open-uri'

class PurgeCacheWorker
  HTTP_TIMEOUT = 3
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 2, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    # return 10 if count < 10
    60
  end

  def perform(proxy_ip, username, path)
    # Must always have a forward slash
    path = '/' + path if path[0] != '/'

    url = Addressable::URI.encode_component(
      "https://#{proxy_ip}#{path}",
      Addressable::URI::CharacterClasses::QUERY
    )

    retry_encoded = false

    begin
      HTTP.timeout(read: 10, write: 10, connect: 2).
        headers(host: URI::encode("#{username}.neocities.org"), cache_purge: '1').
        head(url)
    rescue URI::InvalidURIError
      raise if retry_encoded == true
      url = URI.encode url
      retry_encoded = true
      retry
    end
  end
end
