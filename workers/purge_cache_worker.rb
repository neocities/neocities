class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 10, backtrace: true

  def perform(payload)
    attempt = 0
    begin
      attempt += 1
      $pubsub.publish 'purgecache', payload.to_json
    rescue Redis::BaseConnectionError => error
      raise if attempt > 3
      puts "pubsub error: #{error}, retrying in 1s"
      sleep 1
      retry
    end
  end
end