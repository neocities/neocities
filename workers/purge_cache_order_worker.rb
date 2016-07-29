class PurgeCacheOrderWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecacheorder, retry: 1000, backtrace: true, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  def perform(username, path)
    if ENV['RACK_ENV'] == 'test'
      proxy_ips = ['10.0.0.1', '10.0.0.2']
    else
      #proxy_ips = Resolv.getaddresses($config['cache_purge_ips_uri'])
      proxy_ips = Resolv.getaddresses($config['cache_purge_ips_uri']).keep_if {|r| !r.match(/:/)}
    end

    proxy_ips.each do |proxy_ip|
      PurgeCacheWorker.perform_async proxy_ip, username, path
    end
  end
end
