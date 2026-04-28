class PurgeCacheWorker
  include Sidekiq::Worker

  PURGE_STREAM_KEY = 'cache-purge-stream'
  STREAM_MAX_LENGTH = 10_000
  FOLLOWUP_PURGE_DELAYS = [1.minute, 10.minutes].freeze

  sidekiq_options queue: :purgecache, retry: 10, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    60
  end

  def self.enqueue_purge(username, path)
    perform_async username, path

    FOLLOWUP_PURGE_DELAYS.each do |delay|
      perform_in delay, username, path
    end
  end

  def perform(username, path)
    $redis_proxy.xadd(PURGE_STREAM_KEY, {u: username, p: path}, maxlen: STREAM_MAX_LENGTH, approximate: true)
  end
end
