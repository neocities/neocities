require_relative './environment.rb'

include Rack::Test::Methods

def app
  Sinatra::Application
end

def upload(hash)
  post '/site_files/upload', hash.merge(csrf_token: 'abcd'), {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
end

def delete_file(hash)
  post '/site_files/delete', hash.merge(csrf_token: 'abcd'), {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
end

describe 'site_files' do
  before do
    @site = Fabricate :site
    ThumbnailWorker.jobs.clear
    PurgeCacheWorker.jobs.clear
    ScreenshotWorker.jobs.clear
  end

  describe 'delete' do
    it 'works' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      file_path = @site.files_path 'test.jpg'
      File.exists?(file_path).must_equal true
      delete_file filename: 'test.jpg'
      File.exists?(file_path).must_equal false
      SiteFile[site_id: @site.id, path: 'test.jpg'].must_be_nil
    end
  end

  describe 'upload' do
    it 'manages files with invalid UTF8' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/invalidutf8.html', 'text/html')
      File.exists?(@site.files_path('invalidutf8.html')).must_equal true
    end

    it 'works with manifest files' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/cache.manifest', 'text/cache-manifest')
      File.exists?(@site.files_path('cache.manifest')).must_equal true
    end

    it 'works with otf fonts' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/chunkfive.otf', 'application/vnd.ms-opentype')
      File.exists?(@site.files_path('chunkfive.otf')).must_equal true
    end

    it 'succeeds with index.html file' do
      @site.site_changed.must_equal false
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      last_response.body.must_match /successfully uploaded/i
      File.exists?(@site.files_path('index.html')).must_equal true

      args = ScreenshotWorker.jobs.first['args']
      args.first.must_equal @site.username
      args.last.must_equal 'index.html'
      @site.reload.site_changed.must_equal true
    end

    it 'succeeds with valid file' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      last_response.body.must_match /successfully uploaded/i
      File.exists?(@site.files_path('test.jpg')).must_equal true

      queue_args = PurgeCacheWorker.jobs.first['args'].first
      queue_args['site'].must_equal @site.username
      queue_args['path'].must_equal '/test.jpg'

      ThumbnailWorker.jobs.length.must_equal 1
      ThumbnailWorker.drain

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        File.exists?(@site.thumbnail_path('test.jpg', resolution)).must_equal true
      end

      @site.site_changed.must_equal false
    end

    it 'fails with unsupported file' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
      last_response.body.must_match /only supported by.+supporter account/i
      File.exists?(@site.files_path('flowercrime.wav')).must_equal false
      @site.site_changed.must_equal false
    end

    it 'succeeds for unwhitelisted file on supporter plans' do
      no_file_restriction_plans = Site::PLAN_FEATURES.select {|p,v| v[:no_file_restrictions] == true}
      no_file_restriction_plans.each do |plan_type,hash|
        @site = Fabricate :site, plan_type: plan_type
        upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
        last_response.body.must_match /successfully uploaded/i
        File.exists?(@site.files_path('flowercrime.wav')).must_equal true
      end
    end

    it 'overwrites existing file with new file' do
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      last_response.body.must_match /successfully uploaded/i
      digest = @site.reload.site_files.first.sha1_hash
      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/img/test.jpg', 'image/jpeg')
      last_response.body.must_match /successfully uploaded/i
      @site.reload.changed_count.must_equal 2
      @site.site_files.select {|f| f.path == 'test.jpg'}.length.must_equal 1
      digest.wont_equal @site.site_files_dataset.where(path: 'test.jpg').first.sha1_hash
    end

    it 'works with directory path' do
      upload(
        'dir' => 'derpie/derptest',
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      )
      last_response.body.must_match /successfully uploaded/i
      File.exists?(@site.files_path('derpie/derptest/test.jpg')).must_equal true

      PurgeCacheWorker.jobs.length.must_equal 1
      queue_args = PurgeCacheWorker.jobs.first['args'].first
      queue_args['path'].must_equal '/derpie/derptest/test.jpg'

      ThumbnailWorker.jobs.length.must_equal 1
      ThumbnailWorker.drain

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        File.exists?(@site.thumbnail_path('derpie/derptest/test.jpg', resolution)).must_equal true
        @site.thumbnail_url('derpie/derptest/test.jpg', resolution).must_equal(
          File.join "#{Site::THUMBNAILS_URL_ROOT}", @site.username, "/derpie/derptest/test.jpg.#{resolution}.jpg"
        )
      end
    end

    it 'does not store new file if hash matches' do
      upload(
        'dir' => 'derpie/derptest',
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      )
      @site.reload.changed_count.must_equal 1

      upload(
        'dir' => 'derpie/derptest',
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      )
      @site.reload.changed_count.must_equal 1

      upload 'files[]' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      @site.reload.changed_count.must_equal 2
    end
  end
end