require 'open-uri'

# PurgeCacheWorker refreshes the cache, this actually deletes it.
# This is because when the file is 404ing the PurgeCacheWorker
# will just sit on the stale cache, even though it's not supposed to.
# It's some nginx bug. I'm not going to deal with it.

class DeleteCacheWorker
  HTTP_TIMEOUT = 10
  include Sidekiq::Worker
  sidekiq_options queue: :deletecache, retry: 3, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(proxy_ip, username, path)
    $redis_proxy.publish 'proxy', {cmd: 'purge', path: "#{username}#{path}"}.to_msgpack
  end
end
