require_relative '../environment.rb'

describe ScreenshotWorker do

  it 'saves a screenshot for a root html file' do
    ['index.html', 'derpie/derp/index.html'].each do |path|
      uri = Addressable::URI.parse $config['screenshot_urls'].sample
      site = Fabricate :site

      base_host = "#{uri.scheme}://#{uri.host}"
      if uri.port != 80 && uri.port != 443
        base_host += ":#{uri.port}"
      end

      stub_request(:get, "#{base_host}/?url=#{site.uri(path)}&wait_time=#{ScreenshotWorker::PAGE_WAIT_TIME}").
        with(basic_auth: [uri.user, uri.password]).
        to_return(status: 200, headers: {}, body: File.read('tests/files/img/screenshot.png'))

      ScreenshotWorker.new.perform site.username, path

      Site::SCREENSHOT_RESOLUTIONS.each do |r|
        _(File.exists?(File.join(Site::SCREENSHOTS_ROOT, Site.sharding_dir(site.username), site.username, "#{path}.#{r}.webp"))).must_equal true
        _(site.screenshot_url(path, r)).must_equal(
          File.join(Site::SCREENSHOTS_URL_ROOT, Site.sharding_dir(site.username), site.username, "#{path}.#{r}.webp")
        )
      end
    end
  end
end
