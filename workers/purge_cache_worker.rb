class PurgeCacheWorker
  include Sidekiq::Worker

  PURGE_STREAM_KEY = 'cache-purge-stream'
  STREAM_MAX_LENGTH = 10_000

  sidekiq_options queue: :purgecache, retry: 10, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    60
  end

  def perform(username, path)
    $redis_proxy.xadd(PURGE_STREAM_KEY, {u: username, p: path}, maxlen: STREAM_MAX_LENGTH, approximate: true)
  end
end