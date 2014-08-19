class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 10, backtrace: true

  def perform(payload)
    attempt = 0
    begin
      attempt += 1
      $pubsub_pool.with do |redis|
        redis.publish 'purgecache', payload.to_json
      end
    rescue Redis::BaseConnectionError => error
      raise if attempt > 3
      puts "pubsub error: #{error}, retrying in 1s"
      sleep 1
      retry
    end
  end
end