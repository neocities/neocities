require 'open-uri'

# PurgeCacheWorker refreshes the cache, this actually deletes it.
# This is because when the file is 404ing the PurgeCacheWorker
# will just sit on the stale cache, even though it's not supposed to.
# It's some nginx bug. I'm not going to deal with it.

class DeleteCacheWorker
  HTTP_TIMEOUT = 5
  include Sidekiq::Worker
  sidekiq_options queue: :deletecache, retry: 3, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(proxy_ip, username, path)
    # Must always have a forward slash
    path = '/' + path if path[0] != '/'

    url = Addressable::URI.encode_component(
      "https://#{proxy_ip}/:cache/purge#{path}",
      Addressable::URI::CharacterClasses::QUERY
    )

    HTTP.timeout(read: 10, write: 10, connect: 2).
      headers(host: URI::encode("#{username}.neocities.org")).
      get(url)
  end
end
