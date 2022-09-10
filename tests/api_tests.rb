require_relative './environment.rb'
require 'rack/test'

describe 'api' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def create_site(opts={})
    site_attr = Fabricate.attributes_for :site
    @site = Site.create site_attr.merge(opts)
    @user = site_attr[:username]
    @pass = site_attr[:password]
  end

  def site_file_exists?(file)
    File.exist?(@site.files_path(file))
  end

  def res
    JSON.parse last_response.body, symbolize_names: true
  end

  describe 'not found' do
    it 'returns json for missing route' do
      get '/api/sdlfkjsdlfjds'
      last_response.status.must_equal 404
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'not_found'
    end
  end

  describe 'list' do
    it 'returns all files without path' do
      create_site
      basic_authorize @user, @pass
      get '/api/list'

      res[:result].must_equal 'success'
      res[:files].length.must_equal @site.site_files.length

      res[:files].each do |file|
        site_file = @site.site_files.select {|s| s[:path] == file[:path]}.first
        site_file[:is_directory].must_equal file[:is_directory]
        site_file[:size].must_equal file[:size]
        site_file[:updated_at].rfc2822.must_equal file[:updated_at]
        site_file[:sha1_hash].must_equal file[:sha1_hash]
      end
    end

    it 'shows empty array for missing path' do
      create_site
      basic_authorize @user, @pass
      get '/api/list', path: '/fail'
      res[:result].must_equal 'success'
      res[:files].must_equal []
    end

    it 'shows files in path' do
      create_site
      tempfile = Tempfile.new
      tempfile.write('meep html')
      @site.store_files [{filename: '/derp/test.html', tempfile: tempfile}]
      basic_authorize @user, @pass
      get '/api/list', path: '/derp'
      res[:result].must_equal 'success'
      res[:files].length.must_equal 1
      file = res[:files].first
      file[:path].must_equal 'derp/test.html'
      file[:updated_at].must_equal @site.site_files.select {|s| s.path == 'derp/test.html'}.first.updated_at.rfc2822
    end
  end

  describe 'info' do
    it 'fails for no input' do
      get '/api/info'
      res[:error_type] = 'missing_sitename'
    end

    it 'fails for banned sites' do
      create_site
      @site.update is_banned: true
      get '/api/info', sitename: @site.username
      res[:error_type].must_equal 'site_not_found'
      @site.reload.api_calls.must_equal 0
    end

    it 'fails for nonexistent site' do
      get '/api/info', sitename: 'notexist'
      res[:error_type].must_equal 'site_not_found'
    end

    it 'succeeds for valid sitename' do
      create_site
      @site.update hits: 31337, changed_count: 222, domain: 'derp.com', new_tags_string: 'derpie, man'
      @site.add_archive ipfs_hash: 'QmXGTaGWTT1uUtfSb2sBAvArMEVLK4rQEcQg5bv7wwdzwU'
      get '/api/info', sitename: @user
      res[:result].must_equal 'success'
      res[:info][:sitename].must_equal @site.username
      res[:info][:hits].must_equal 31337
      res[:info][:updates].must_equal 222
      res[:info][:created_at].must_equal @site.created_at.rfc2822
      res[:info][:last_updated].must_be_nil
      res[:info][:domain].must_equal 'derp.com'
      res[:info][:tags].must_equal ['derpie', 'man']
      res[:info][:latest_ipfs_hash].must_equal 'QmXGTaGWTT1uUtfSb2sBAvArMEVLK4rQEcQg5bv7wwdzwU'
      @site.reload.api_calls.must_equal 0
    end

    it 'shows latest ipfs hash as nil when not present' do
      create_site
      get '/api/info', sitename: @user
      res[:info][:latest_ipfs_hash].must_be_nil
    end

    it 'fails for bad auth' do
      basic_authorize 'derp', 'fake'
      get '/api/info'
      res[:error_type].must_equal 'invalid_auth'
    end

    it 'succeeds for api auth' do
      create_site
      @site.update hits: 12345
      basic_authorize @user, @pass
      get '/api/info'
      res[:info][:hits] == 12345
    end
  end

  describe 'delete' do
    it 'fails with no or bad auth' do
      post '/api/delete', filenames: ['hi.html']
      res[:error_type].must_equal 'invalid_auth'
      create_site
      basic_authorize 'derp', 'fake'
      post '/api/delete', filenames: ['hi.html']
      res[:error_type].must_equal 'invalid_auth'
    end

    it 'fails with missing filename argument' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete'
      res[:error_type].must_equal 'missing_filenames'
    end

    it 'fails to delete index.html' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['index.html']
      res[:error_type].must_equal 'cannot_delete_index'
    end

    it 'succeeds with weird filenames' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 't$st.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['t$st.jpg']
      res[:result].must_equal 'success'

      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['./config.yml']
      res[:error_type].must_equal 'missing_files'
    end

    it 'fails with missing files' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 'test.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['doesntexist.jpg']
      res[:error_type].must_equal 'missing_files'
    end

    it 'fails to delete site directory' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['/']
      res[:error_type].must_equal 'cannot_delete_site_directory'
      File.exist?(@site.files_path).must_equal true
    end

    it 'fails to delete other directories' do
      create_site
      @other_site = @site
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ["../#{@other_site.username}"]
      File.exist?(@other_site.base_files_path).must_equal true
      res[:error_type].must_equal 'missing_files'
      post '/api/delete', filenames: ["../#{@other_site.username}/index.html"]
      File.exist?(@other_site.base_files_path+'/index.html').must_equal true
      res[:error_type].must_equal 'missing_files'
    end

    it 'succeeds with valid filenames' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 'test.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      @site.store_files [{filename: 'test2.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['test.jpg', 'test2.jpg']
      res[:result].must_equal 'success'
      site_file_exists?('test.jpg').must_equal false
      site_file_exists?('test2.jpg').must_equal false
    end
  end

  describe 'key' do
    it 'generates new key with valid login' do
      create_site
      basic_authorize @user, @pass
      get '/api/key'
      res[:result].must_equal 'success'
      res[:api_key].must_equal @site.reload.api_key
    end

    it 'returns existing key' do
      create_site
      @site.generate_api_key!
      basic_authorize @user, @pass
      get '/api/key'
      res[:api_key].must_equal @site.api_key
    end

    it 'fails for bad login' do
      create_site
      basic_authorize 'zero', 'cool'
      get '/api/key'
      res[:error_type].must_equal 'invalid_auth'
    end
  end

  describe 'upload hash' do
    it 'succeeds' do
      create_site
      basic_authorize @user, @pass
      test_hash = Digest::SHA1.file('./tests/files/test.jpg').hexdigest

      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'test2.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }

      post '/api/upload_hash', "test.jpg" => test_hash, "test2.jpg" => Digest::SHA1.hexdigest('herpderp')

      res[:result].must_equal 'success'
      res[:files][:'test.jpg'].must_equal true
      res[:files][:'test2.jpg'].must_equal false
    end
  end

  describe 'rename' do
    before do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'testdir/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
    end

    it 'succeeds' do
      post '/api/rename', path: 'testdir/test.jpg', new_path: 'testdir/test2.jpg'
      res[:result].must_equal 'success'
    end

    it 'fails to overwrite index file' do
      post '/api/rename', path: 'testdir/test.jpg', new_path: 'index.html'
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'rename_error'
      res[:message].must_equal 'file already exists'
    end

    it 'fails to overwrite existing file' do
      post '/api/rename', path: 'testdir/test.jpg', new_path: 'not_found.html'
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'rename_error'
    end

    it 'succeeds with directory' do
      @site.create_directory 'derpiedir'
      post '/api/rename', path: 'derpiedir', new_path: 'notderpiedir'
      res[:result].must_equal 'success'
    end
  end

  describe 'upload' do
    it 'fails with no auth' do
      post '/api/upload'
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'invalid_auth'
    end

    it 'fails for bad auth' do
      basic_authorize 'username', 'password'
      post '/api/upload'
      res[:error_type].must_equal 'invalid_auth'
    end

    it 'fails with missing files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload'
      res[:error_type].must_equal 'missing_files'
    end

    it 'succeeds with valid api key' do
      create_site
      @site.api_key.must_be_nil
      @site.generate_api_key!
      @site.reload.api_key.wont_equal nil
      header 'Authorization', "Bearer #{@site.api_key}"
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      res[:result].must_equal 'success'
      site_file_exists?('test.jpg').must_equal true
    end

    it 'fails with bad api key' do
      create_site
      @site.generate_api_key!
      header 'Authorization', "Bearer zerocool"
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'invalid_auth'
    end

=begin
  # Getting too slow to run this test
  it 'fails with too many files' do
    create_site
    basic_authorize @user, @pass
    @site.plan_feature(:maximum_site_files).times {
      uuid = SecureRandom.uuid.gsub('-', '')+'.html'
      @site.add_site_file path: uuid
    }
    post '/api/upload', {
      '/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    }
    res[:error_type].must_equal 'too_many_files'
  end
=end

    it 'resists directory traversal attack' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '../lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:result].must_equal 'success'
      File.exist?(File.join(Site::SITE_FILES_ROOT, Site.sharding_dir(@site.username), @site.username, 'lol.jpg')).must_equal true
      @site.reload.api_calls.must_equal 1
    end

    it 'scrubs root path slash' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:result].must_equal 'success'
      File.exist?(File.join(Site::SITE_FILES_ROOT, Site.sharding_dir(@site.username), @site.username, 'lol.jpg')).must_equal true
    end

    it 'fails for missing file name' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '/' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:error_type].must_equal 'invalid_file_type'
    end

    it 'fails for file with no extension' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'derpie' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:error_type].must_equal 'invalid_file_type'
    end

    it 'creates path for file uploads' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'derpie/derpingtons/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:result].must_equal 'success'
      File.exist?(@site.files_path('derpie/derpingtons/lol.jpg')).must_equal true
    end

    it 'records api calls that require auth' do
      create_site
      basic_authorize @user, @pass

      2.times {
        post '/api/upload', {
          'derpie/derpingtons/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
        }
      }

      @site.reload.api_calls.must_equal 2
    end

    it 'fails for invalid files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'nord.avi' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'image/jpeg')
      }
      res[:error_type].must_equal 'invalid_file_type'
      site_file_exists?('test.jpg').must_equal false
      site_file_exists?('nord.avi').must_equal false
    end

    it 'succeeds with single file' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      res[:result].must_equal 'success'
      site_file_exists?('test.jpg').must_equal true
    end

    it 'succeeds with two files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'test2.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      res[:result].must_equal 'success'
      site_file_exists?('test.jpg').must_equal true
      site_file_exists?('test2.jpg').must_equal true
    end

    it 'fails with unwhitelisted file' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
      res[:result].must_equal 'error'
      res[:error_type].must_equal 'invalid_file_type'
      site_file_exists?('flowercrime.wav').must_equal false
    end

    it 'succeeds for unwhitelisted file on supported plans' do
      no_file_restriction_plans = Site::PLAN_FEATURES.select {|p,v| v[:no_file_restrictions] == true}
      no_file_restriction_plans.each do |plan_type,hash|
        create_site plan_type: plan_type
        basic_authorize @user, @pass
        post '/api/upload', 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
        res[:result].must_equal 'success'
        site_file_exists?('flowercrime.wav').must_equal true
      end
    end
  end
end
