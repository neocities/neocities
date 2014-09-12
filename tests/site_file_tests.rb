require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe 'site_files' do
  describe 'upload' do
    it 'succeeds with index.html file' do
      site = Fabricate :site
      site.site_changed.must_equal false
      PurgeCacheWorker.jobs.clear
      ScreenshotWorker.jobs.clear

      post '/site_files/upload', {
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html'),
        'csrf_token' => 'abcd'
      }, {'rack.session' => { 'id' => site.id, '_csrf_token' => 'abcd' }}
      last_response.body.must_match /successfully uploaded/i
      File.exists?(site.files_path('index.html')).must_equal true

      args = ScreenshotWorker.jobs.first['args']
      args.first.must_equal site.username
      args.last.must_equal 'index.html'
      site.reload.site_changed.must_equal true
    end

    it 'succeeds with valid file' do
      site = Fabricate :site
      PurgeCacheWorker.jobs.clear
      ThumbnailWorker.jobs.clear
      post '/site_files/upload', {
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'csrf_token' => 'abcd'
      }, {'rack.session' => { 'id' => site.id, '_csrf_token' => 'abcd' }}
      last_response.body.must_match /successfully uploaded/i
      File.exists?(site.files_path('test.jpg')).must_equal true

      queue_args = PurgeCacheWorker.jobs.first['args'].first
      queue_args['site'].must_equal site.username
      queue_args['path'].must_equal '/test.jpg'

      ThumbnailWorker.jobs.length.must_equal 1
      ThumbnailWorker.drain

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        File.exists?(site.thumbnail_path('test.jpg', resolution)).must_equal true
      end

      site.site_changed.must_equal false
    end

    it 'works with directory path' do
      site = Fabricate :site
      ThumbnailWorker.jobs.clear
      PurgeCacheWorker.jobs.clear
      post '/site_files/upload', {
        'dir' => 'derpie/derptest',
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'csrf_token' => 'abcd'
      }, {'rack.session' => { 'id' => site.id, '_csrf_token' => 'abcd' }}
      last_response.body.must_match /successfully uploaded/i
      File.exists?(site.files_path('derpie/derptest/test.jpg')).must_equal true

      PurgeCacheWorker.jobs.length.must_equal 1
      queue_args = PurgeCacheWorker.jobs.first['args'].first
      queue_args['path'].must_equal '/derpie/derptest/test.jpg'

      ThumbnailWorker.jobs.length.must_equal 1
      ThumbnailWorker.drain

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        File.exists?(site.thumbnail_path('derpie/derptest/test.jpg', resolution)).must_equal true
        site.thumbnail_url('derpie/derptest/test.jpg', resolution).must_equal(
          File.join "#{Site::THUMBNAILS_URL_ROOT}", site.username, "/derpie/derptest/test.jpg.#{resolution}.jpg"
        )
      end
    end
  end
end