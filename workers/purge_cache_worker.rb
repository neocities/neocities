require 'open-uri'

class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 1000, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(proxy_ip, username, path)
    # Must always have a forward slash
    path = '/' + path if path[0] != '/'

    url = Addressable::URI.encode_component(
      "http://#{proxy_ip}/:cache/purge#{path}",
      Addressable::URI::CharacterClasses::QUERY
    )
    begin
      RestClient.get(url, host: URI::encode("#{username}.neocities.org"))
    rescue RestClient::ResourceNotFound
    end
  end
end
