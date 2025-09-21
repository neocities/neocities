# frozen_string_literal: true
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
      _(last_response.status).must_equal 404
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'not_found'
    end
  end

  describe 'list' do
    it 'returns all files without path' do
      create_site
      basic_authorize @user, @pass
      get '/api/list'

      _(res[:result]).must_equal 'success'
      _(res[:files].length).must_equal @site.site_files.length

      res[:files].each do |file|
        site_file = @site.site_files.select {|s| s[:path] == file[:path]}.first
        _(site_file[:is_directory]).must_equal file[:is_directory]
        _(site_file[:size]).must_equal file[:size]
        _(site_file[:updated_at].rfc2822).must_equal file[:updated_at]
        _(site_file[:sha1_hash]).must_equal file[:sha1_hash]
      end
    end

    it 'shows empty array for missing path' do
      create_site
      basic_authorize @user, @pass
      get '/api/list', path: '/fail'
      _(res[:result]).must_equal 'success'
      _(res[:files]).must_equal []
    end

    it 'shows files in path' do
      create_site
      tempfile = Tempfile.new
      tempfile.write('meep html')
      @site.store_files [{filename: '/derp/test.html', tempfile: tempfile}]
      basic_authorize @user, @pass
      get '/api/list', path: '/derp'
      _(res[:result]).must_equal 'success'
      _(res[:files].length).must_equal 1
      file = res[:files].first
      _(file[:path]).must_equal 'derp/test.html'
      _(file[:updated_at]).must_equal @site.site_files.select {|s| s.path == 'derp/test.html'}.first.updated_at.rfc2822
    end

    it 'returns all files when path is /' do
      create_site
      basic_authorize @user, @pass
      get '/api/list', path: '/'

      _(res[:result]).must_equal 'success'
      _(res[:files].length).must_equal @site.site_files.length

      res[:files].each do |file|
        site_file = @site.site_files.select {|s| s[:path] == file[:path]}.first
        _(site_file[:is_directory]).must_equal file[:is_directory]
        _(site_file[:size]).must_equal file[:size]
        _(site_file[:updated_at].rfc2822).must_equal file[:updated_at]
        _(site_file[:sha1_hash]).must_equal file[:sha1_hash]
      end
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
      _(res[:error_type]).must_equal 'site_not_found'
      _(@site.reload.api_calls).must_equal 0
    end

    it 'fails for nonexistent site' do
      get '/api/info', sitename: 'notexist'
      _(res[:error_type]).must_equal 'site_not_found'
    end

    it 'succeeds for valid sitename' do
      create_site
      @site.update hits: 31337, domain: 'derp.com', new_tags_string: 'derpie, man'
      get '/api/info', sitename: @user
      _(res[:result]).must_equal 'success'
      _(res[:info][:sitename]).must_equal @site.username
      _(res[:info][:hits]).must_equal 31337
      _(res[:info][:created_at]).must_equal @site.created_at.rfc2822
      _(res[:info][:last_updated]).must_be_nil
      _(res[:info][:domain]).must_equal 'derp.com'
      _(res[:info][:tags]).must_equal ['derpie', 'man']
      _(@site.reload.api_calls).must_equal 0
    end

    it 'fails for bad auth' do
      basic_authorize 'derp', 'fake'
      get '/api/info'
      _(res[:error_type]).must_equal 'invalid_auth'
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
      _(res[:error_type]).must_equal 'invalid_auth'
      create_site
      basic_authorize 'derp', 'fake'
      post '/api/delete', filenames: ['hi.html']
      _(res[:error_type]).must_equal 'invalid_auth'
    end

    it 'fails with missing filename argument' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete'
      _(res[:error_type]).must_equal 'missing_filenames'
    end

    it 'fails to delete index.html' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['index.html']
      _(res[:error_type]).must_equal 'cannot_delete_index'
    end

    it 'succeeds with weird filenames' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 't$st.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['t$st.jpg']
      _(res[:result]).must_equal 'success'

      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['./config.yml']
      _(res[:error_type]).must_equal 'missing_files'
    end

    it 'fails with missing files' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 'test.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['doesntexist.jpg']
      _(res[:error_type]).must_equal 'missing_files'
    end

    it 'fails to delete site directory' do
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ['/']
      _(res[:error_type]).must_equal 'cannot_delete_site_directory'
      _(File.exist?(@site.files_path)).must_equal true
    end

    it 'fails to delete other directories' do
      create_site
      @other_site = @site
      create_site
      basic_authorize @user, @pass
      post '/api/delete', filenames: ["../#{@other_site.username}"]
      _(File.exist?(@other_site.base_files_path)).must_equal true
      _(res[:error_type]).must_equal 'missing_files'
      post '/api/delete', filenames: ["../#{@other_site.username}/index.html"]
      _(File.exist?(@other_site.base_files_path+'/index.html')).must_equal true
      _(res[:error_type]).must_equal 'missing_files'
    end

    it 'succeeds with valid filenames' do
      create_site
      basic_authorize @user, @pass
      @site.store_files [{filename: 'test.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      @site.store_files [{filename: 'test2.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
      post '/api/delete', filenames: ['test.jpg', 'test2.jpg']
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('test.jpg')).must_equal false
      _(site_file_exists?('test2.jpg')).must_equal false
    end
  end

  describe 'key' do
    it 'generates new key with valid login' do
      create_site
      basic_authorize @user, @pass
      get '/api/key'
      _(res[:result]).must_equal 'success'
      _(res[:api_key]).must_equal @site.reload.api_key
    end

    it 'returns existing key' do
      create_site
      @site.generate_api_key!
      basic_authorize @user, @pass
      get '/api/key'
      _(res[:api_key]).must_equal @site.api_key
    end

    it 'fails for bad login' do
      create_site
      basic_authorize 'zero', 'cool'
      get '/api/key'
      _(res[:error_type]).must_equal 'invalid_auth'
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

      _(res[:result]).must_equal 'success'
      _(res[:files][:'test.jpg']).must_equal true
      _(res[:files][:'test2.jpg']).must_equal false
    end

    it 'rejects nested parameter structures' do
      create_site
      basic_authorize @user, @pass

      post '/api/upload_hash', {
        "one/two" => {
          "three" => {
            ".jpg" => "196b99a0ab80d1fc2e7caf49d98e8dd76db25c72"
          }
        }
      }

      _(last_response.status).must_equal 400
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'nested_parameters_not_allowed'
      _(res[:message]).must_equal 'nested parameters are not allowed; each path must directly map to a SHA-1 hash string'
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
      _(res[:result]).must_equal 'success'
    end

    it 'fails to overwrite index file' do
      post '/api/rename', path: 'testdir/test.jpg', new_path: 'index.html'
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'rename_error'
      _(res[:message]).must_equal 'file already exists'
    end

    it 'fails to overwrite existing file' do
      post '/api/rename', path: 'testdir/test.jpg', new_path: 'not_found.html'
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'rename_error'
    end

    it 'succeeds with directory' do
      @site.create_directory 'derpiedir'
      post '/api/rename', path: 'derpiedir', new_path: 'notderpiedir'
      _(res[:result]).must_equal 'success'
    end
  end

  describe 'upload' do
    it 'fails with no auth' do
      post '/api/upload'
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'invalid_auth'
    end

    it 'fails for bad auth' do
      basic_authorize 'username', 'password'
      post '/api/upload'
      _(res[:error_type]).must_equal 'invalid_auth'
    end

    it 'fails with missing files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload'
      _(res[:error_type]).must_equal 'missing_files'
    end

    it 'succeeds with valid api key' do
      create_site
      _(@site.api_key).must_be_nil
      @site.generate_api_key!
      _(@site.reload.api_key).wont_equal nil
      header 'Authorization', "Bearer #{@site.api_key}"
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('test.jpg')).must_equal true
    end

    it 'fails api_key auth unless controls site' do
      create_site
      @site.generate_api_key!
      @other_site = Fabricate :site
      header 'Authorization', "Bearer #{@site.api_key}"
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'), 'username' => @other_site.username

      _(res[:result]).must_equal 'error'
      _(@other_site.site_files.select {|s| s.path == 'test.jpg'}).must_equal []
      _(res[:error_type]).must_equal 'site_not_allowed'
    end

    it 'succeeds with square bracket in filename' do
      create_site
      @site.generate_api_key!
      header 'Authorization', "Bearer #{@site.api_key}"
      post '/api/upload', 'te[s]t.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('te[s]t.jpg')).must_equal true
    end

    it 'succeeds with percent character in filename' do
      create_site
      @site.generate_api_key!
      header 'Authorization', "Bearer #{@site.api_key}"

      test_filenames = [
        '100% awesome.jpg',
        'dsfds/50%off.png',
        '50% sale.txt',
        'discount%special.png'
      ]

      test_filenames.each do |filename|
        post '/api/upload', filename => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
        _(res[:result]).must_equal 'success'
        _(site_file_exists?(filename)).must_equal true

        # Verify the filename was stored literally, not URL-decoded
        @site.reload  # Reload to get fresh site_files
        site_file = @site.site_files.find { |f| f.path == filename }
        _(site_file).wont_be_nil
        _(site_file.path).must_equal filename  # Should be exactly as uploaded
      end
    end

    it 'succeeds with valid user session' do
      create_site
      post '/api/upload',
           {'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
            'csrf_token' => 'abcd'},
           {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}

      _(res[:result]).must_equal 'success'
      _(last_response.status).must_equal 200
      _(site_file_exists?('test.jpg')).must_equal true
    end

    it 'succeeds with valid user session controlled site' do
      create_site
      @other_site = Fabricate :site, parent_site_id: @site.id
      post '/api/upload',
           {'test.jpg'     => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
            'csrf_token'   => 'abcd',
            'username'     => @other_site.username},
           {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}

      _(res[:result]).must_equal 'success'
      _(last_response.status).must_equal 200
      _(@other_site.site_files.select {|sf| sf.path == 'test.jpg'}.length).must_equal 1
    end

    it 'fails session upload unless controls site' do
      create_site
      @other_site = Fabricate :site
      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'username' => @other_site.username,
        'csrf_token' => 'abcd'},
        {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}

      _(res[:result]).must_equal 'error'
      _(@other_site.site_files.select {|s| s.path == 'test.jpg'}).must_equal []
      _(res[:error_type]).must_equal 'site_not_allowed'
    end

    it 'fails with bad api key' do
      create_site
      @site.generate_api_key!
      header 'Authorization', "Bearer zerocool"
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'invalid_auth'
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
    _(res[:error_type]).must_equal 'too_many_files'
  end
=end

    it 'resists directory traversal attack' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '../lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'invalid_filename'
      _(File.exist?(File.join(Site::SITE_FILES_ROOT, Site.sharding_dir(@site.username), @site.username, 'lol.jpg'))).must_equal false
    end

    it 'scrubs root path slash' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:result]).must_equal 'success'
      _(File.exist?(File.join(Site::SITE_FILES_ROOT, Site.sharding_dir(@site.username), @site.username, 'lol.jpg'))).must_equal true
    end

    it 'fails for missing file name' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        '/' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:error_type]).must_equal 'invalid_filename'
    end

    it 'succeeds for plain text file with no extension' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'LICENSE' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      }
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('LICENSE')).must_equal true
    end

    it 'fails for non-text file with no extension' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'binaryfile' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:error_type]).must_equal 'invalid_file_type'
    end

    it 'creates path for file uploads' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'derpie/derpingtons/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:result]).must_equal 'success'
      _(File.exist?(@site.files_path('derpie/derpingtons/lol.jpg'))).must_equal true
    end

    it 'records api calls that require auth' do
      create_site
      basic_authorize @user, @pass

      2.times {
        post '/api/upload', {
          'derpie/derpingtons/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
        }
      }

      _(@site.reload.api_calls).must_equal 2
    end

    it 'fails for invalid files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'nord.avi' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'image/jpeg')
      }
      _(res[:error_type]).must_equal 'invalid_file_type'
      _(site_file_exists?('test.jpg')).must_equal false
      _(site_file_exists?('nord.avi')).must_equal false
    end

    it 'fails for invalid filenames' do
      create_site
      basic_authorize @user, @pass

      ['.', '..', '/.', '/..'].each do |invalid_filename|
        post '/api/upload', {
          invalid_filename => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
        }
        _(res[:result]).must_equal 'error'
        _(res[:error_type]).must_equal 'invalid_filename'
        _(res[:message]).must_include invalid_filename
      end
    end

    it 'succeeds with single file' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('test.jpg')).must_equal true
    end

    it 'works with unicode chars on filename and dir' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', '詩經/詩經.jpg' => Rack::Test::UploadedFile.new('./tests/files/詩經.jpg', 'image/jpeg')
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('詩經/詩經.jpg')).must_equal true
    end

    it 'succeeds with two files' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', {
        'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'test2.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      }
      _(res[:result]).must_equal 'success'
      _(site_file_exists?('test.jpg')).must_equal true
      _(site_file_exists?('test2.jpg')).must_equal true
    end

    it 'fails when file conflicts with existing directory' do
      create_site
      
      # Create a directory at the target path
      @site.create_directory('test.html')

      basic_authorize @user, @pass
      post '/api/upload', {
        'test.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      }

      # Should return error
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'directory_exists'
      _(res[:message]).must_match /conflicts with an existing directory/
      
      # Directory should still exist
      _(@site.is_directory?('test.html')).must_equal true
    end

    it 'fails with unwhitelisted file' do
      create_site
      basic_authorize @user, @pass
      post '/api/upload', 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
      _(res[:result]).must_equal 'error'
      _(res[:error_type]).must_equal 'invalid_file_type'
      _(site_file_exists?('flowercrime.wav')).must_equal false
    end

    it 'succeeds for unwhitelisted file on supported plans' do
      no_file_restriction_plans = Site::PLAN_FEATURES.select {|p,v| v[:no_file_restrictions] == true}
      no_file_restriction_plans.each do |plan_type,hash|
        create_site plan_type: plan_type.to_s
        basic_authorize @user, @pass
        post '/api/upload', 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
        _(res[:result]).must_equal 'success'
        _(site_file_exists?('flowercrime.wav')).must_equal true
      end
    end
  end
end
