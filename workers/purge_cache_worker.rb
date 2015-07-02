class PurgeCacheWorker
  include Sidekiq::Worker
  sidekiq_options queue: :purgecache, retry: 10, backtrace: true

  def perform(subdomain, path)
    res = Dnsruby::Resolver.new

    if ENV['RACK_ENV'] == 'test'
      proxy_ips = ['10.0.0.1', '10.0.0.2']
    else
      proxy_ips = res.query($config['cache_purge_ips_uri']).answer.collect {|a| a.address.to_s}
    end

    proxy_ips.each do |proxy_ip|
      url = "http://#{proxy_ip}/:cache/purge#{path}"

      begin
        RestClient.get(url, host: "#{subdomain}.neocities.org")
      rescue RestClient::ResourceNotFound
      end
    end
  end
end
