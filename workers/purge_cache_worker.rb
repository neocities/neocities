class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 10, backtrace: true

  def perform(url)
    begin
      $pubsub.publish 'purgecache', url
    rescue Redis::BaseConnectionError => error
      puts "Pubsub error: #{error}, retrying in 1s"
      sleep 1
      retry
    end
  end
end