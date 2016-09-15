require 'open-uri'

class PurgeCacheWorker
  HTTP_TIMEOUT = 5
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 3, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(proxy_ip, username, path)
    # Must always have a forward slash
    path = '/' + path if path[0] != '/'

    url = Addressable::URI.encode_component(
      "http://#{proxy_ip}#{path}",
      Addressable::URI::CharacterClasses::QUERY
    )

    retry_encoded = false

    begin
      RestClient::Request.execute method: :head, url: url, timeout: HTTP_TIMEOUT, headers: {
        host: URI::encode("#{username}.neocities.org"),
        cache_purge: '1'
      }
    rescue URI::InvalidURIError
      raise if retry_encoded == true
      url = URI.encode url
      retry_encoded = true
      retry
    rescue RestClient::ResourceNotFound
    rescue RestClient::Forbidden
    end
  end
end
