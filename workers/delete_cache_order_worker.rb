class DeleteCacheOrderWorker
  include Sidekiq::Worker
  sidekiq_options queue: :deletecacheorder, retry: 1000, backtrace: true, average_scheduled_poll_interval: 1

  sidekiq_retry_in do |count|
    return 10 if count < 10
    180
  end

  RESOLVER = Dnsruby::Resolver.new

  def perform(username, path)
    if ENV['RACK_ENV'] == 'test'
      proxy_ips = ['10.0.0.1', '10.0.0.2']
    else
      proxy_ips = Resolv.getaddresses($config['cache_purge_ips_uri'])
    end

    proxy_ips.each do |proxy_ip|
      DeleteCacheWorker.perform_async proxy_ip, username, path
    end
  end
end
