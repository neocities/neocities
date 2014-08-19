require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

def create_site
  site_attr = Fabricate.attributes_for :site
  @site = Site.create site_attr
  @user = site_attr[:username]
  @pass = site_attr[:password]
end

describe 'api info' do
  it 'fails for no input' do
    get '/api/info'
    res[:error_type] = 'missing_sitename'
  end

  it 'fails for banned sites' do
    create_site
    @site.update is_banned: true
    get '/api/info', sitename: @site.username
    res[:error_type].must_equal 'site_not_found'
  end

  it 'fails for nonexistent site' do
    get '/api/info', sitename: 'notexist'
    res[:error_type].must_equal 'site_not_found'
  end

  it 'succeeds for valid sitename' do
    create_site
    @site.update hits: 31337, domain: 'derp.com', new_tags_string: 'derpie, man'
    get '/api/info', sitename: @user
    res[:result].must_equal 'success'
    res[:info][:sitename].must_equal @site.username
    res[:info][:hits].must_equal 31337
    res[:info][:created_at].must_equal @site.created_at.rfc2822
    res[:info][:last_updated].must_equal @site.updated_at.rfc2822
    res[:info][:domain].must_equal 'derp.com'
    res[:info][:tags].must_equal ['derpie', 'man']
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

describe 'api delete' do
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
    @site.store_file 't$st.jpg', Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
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
    @site.store_file 'test.jpg', Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    post '/api/delete', filenames: ['doesntexist.jpg']
    res[:error_type].must_equal 'missing_files'
  end

  it 'succeeds with valid filenames' do
    create_site
    basic_authorize @user, @pass
    @site.store_file 'test.jpg', Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    @site.store_file 'test2.jpg', Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    post '/api/delete', filenames: ['test.jpg', 'test2.jpg']
    res[:result].must_equal 'success'
    site_file_exists?('test.jpg').must_equal false
    site_file_exists?('test2.jpg').must_equal false
  end
end

describe 'api upload' do
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

  it 'resists directory traversal attack' do
    create_site
    basic_authorize @user, @pass
    post '/api/upload', {
      '../lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    }
    res[:result].must_equal 'success'
    File.exist?(File.join(Site::SITE_FILES_ROOT, @site.username, 'lol.jpg')).must_equal true
  end

  it 'scrubs root path slash' do
    create_site
    basic_authorize @user, @pass
    post '/api/upload', {
      '/lol.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    }
    res[:result].must_equal 'success'
    File.exist?(File.join(Site::SITE_FILES_ROOT, @site.username, 'lol.jpg')).must_equal true
  end

  it 'fails for missing file name' do
    create_site
    basic_authorize @user, @pass
    post '/api/upload', {
      '/' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    }
    res[:error_type].must_equal 'invalid_file_type'

    create_site
    basic_authorize @user, @pass
    post '/api/upload', {
      '' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
    }
    res[:error_type].must_equal 'missing_files'
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
end

def site_file_exists?(file)
  File.exist?(@site.files_path('test.jpg'))
end

def res
  JSON.parse last_response.body, symbolize_names: true
end

