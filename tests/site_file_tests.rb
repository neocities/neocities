require_relative './environment.rb'
require 'rack/test'

include Rack::Test::Methods

def app
  Sinatra::Application
end

describe 'site_files' do
  describe 'upload' do
    it 'succeeds with valid file' do
      site = Fabricate :site
      post '/site_files/upload', {
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'csrf_token' => 'abcd'
      }, {'rack.session' => { 'id' => site.id, '_csrf_token' => 'abcd' }}
      last_response.body.must_match /successfully uploaded/i
      File.exists?(site.files_path('test.jpg')).must_equal true
    end

    it 'works with directory path' do
      site = Fabricate :site
      post '/site_files/upload', {
        'dir' => 'derpie/derptest',
        'files[]' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'csrf_token' => 'abcd'
      }, {'rack.session' => { 'id' => site.id, '_csrf_token' => 'abcd' }}
      last_response.body.must_match /successfully uploaded/i
      File.exists?(site.files_path('derpie/derptest/test.jpg')).must_equal true
    end
  end
end