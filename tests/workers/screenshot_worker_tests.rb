require_relative '../environment.rb'

describe ScreenshotWorker do

  it 'saves a screenshot for a root html file' do
    worker = ScreenshotWorker.new
    worker.perform 'kyledrake', 'index.html'
    site = Fabricate :site
    Site::SCREENSHOT_RESOLUTIONS.each do |r|
      File.exists?(File.join(Site::SCREENSHOTS_ROOT, 'kyledrake', "index.html.#{r}.jpg")).must_equal true
      site.screenshot_url('index.html', r).must_equal(
        File.join(Site::SCREENSHOTS_URL_ROOT, site.username, "index.html.#{r}.jpg")
      )
    end
  end

  it 'saves a screenshot for a path html file' do
    worker = ScreenshotWorker.new
    worker.perform 'kyledrake', 'derpie/derp/index.html'
    site = Fabricate :site
    Site::SCREENSHOT_RESOLUTIONS.each do |r|
      File.exists?(File.join(Site::SCREENSHOTS_ROOT, 'kyledrake', "derpie/derp/index.html.#{r}.jpg")).must_equal true
      site.screenshot_url('derpie/derp/index.html', r).must_equal(
        File.join(Site::SCREENSHOTS_URL_ROOT, site.username, "derpie/derp/index.html.#{r}.jpg")
      )
    end
  end
end