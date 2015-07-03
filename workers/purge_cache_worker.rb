class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 1000, backtrace: false, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(proxy_ip, username, path)
    url = "http://#{proxy_ip}/:cache/purge#{path}"
    begin
      RestClient.get(url, host: "#{username}.neocities.org")
    rescue RestClient::ResourceNotFound
    end
  end
end
