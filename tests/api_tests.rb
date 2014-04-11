require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe 'api upload' do
  def create_site
    site_attr = Fabricate.attributes_for :site
    @site = Site.create site_attr
    @user = site_attr[:username]
    @pass = site_attr[:password]
  end

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
  File.exist?(@site.file_path('test.jpg'))
end

def res
  JSON.parse last_response.body, symbolize_names: true
end

