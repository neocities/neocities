require_relative '../environment.rb'

describe ScreenshotWorker do

  it 'saves a screenshot for a root html file' do
    ['index.html', 'derpie/derp/index.html'].each do |path|
      uri = Addressable::URI.parse $config['screenshots_url']
      site = Fabricate :site

      stub_request(:get, "#{uri.scheme}://#{uri.host}/?url=#{site.uri}/#{path}&wait_time=#{ScreenshotWorker::PAGE_WAIT_TIME}").
        with(basic_auth: [uri.user, uri.password]).
        to_return(status: 200, headers: {}, body: File.read('tests/files/img/test.jpg'))

      ScreenshotWorker.new.perform site.username, path

      Site::SCREENSHOT_RESOLUTIONS.each do |r|
        File.exists?(File.join(Site::SCREENSHOTS_ROOT, Site.sharding_dir(site.username), site.username, "#{path}.#{r}.jpg")).must_equal true
        site.screenshot_url(path, r).must_equal(
          File.join(Site::SCREENSHOTS_URL_ROOT, Site.sharding_dir(site.username), site.username, "#{path}.#{r}.jpg")
        )
      end
    end
  end
end
