require 'open-uri'

class PurgeCacheWorker
  HTTP_TIMEOUT = 10
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 2, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    # return 10 if count < 10
    60
  end

  def perform(username, path)
    $redis_proxy.publish 'proxy', {cmd: 'purge', path: "#{username}#{path}"}.to_msgpack
  end
end
