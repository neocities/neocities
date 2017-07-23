require 'open-uri'

class PurgeCacheWorker
  HTTP_TIMEOUT = 10
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 2, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    # return 10 if count < 10
    60
  end

  def perform(proxy_ip, username, path)
    # Must always have a forward slash
    path = '/' + path if path[0] != '/'

    $redis_proxy.publish 'proxy', {cmd: 'purge', key: "#{username}#{path}"}.to_msgpack

    url = Addressable::URI.encode_component(
      "https://#{proxy_ip}#{path}",
      Addressable::URI::CharacterClasses::QUERY
    )

    retry_encoded = false

    begin
      #cmd = %{timeout 5 curl -k -I -H "Host: #{URI::encode("#{username}.neocities.org")}" -H "Cache-Purge: 1" "#{url}"}
      #`#{cmd}`
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      HTTP.follow.timeout(read: 10, write: 10, connect: 5).
        headers(host: URI::encode("#{username}.neocities.org"), cache_purge: '1').
        head(url, ssl_context: ctx)
    rescue URI::InvalidURIError
      raise if retry_encoded == true
      url = URI.encode url
      retry_encoded = true
      retry
    end
  end
end
