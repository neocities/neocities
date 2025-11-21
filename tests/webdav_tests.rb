# frozen_string_literal: true

require_relative './environment.rb'
require 'rack/test'
require 'nokogiri'
require 'rack/utils'

describe 'webdav' do
  include Rack::Test::Methods

  def app
    @app ||= begin
      builder = Rack::Builder.parse_file('config.ru')
      builder = builder.first if builder.is_a?(Array)
      builder = builder.to_app if builder.respond_to?(:to_app)
      builder
    end
  end

  before do
    @site = Fabricate(:site)
    @site.update(plan_type: 'supporter')
    ThumbnailWorker.jobs.clear
    PurgeCacheWorker.jobs.clear
    ScreenshotWorker.jobs.clear
  end

  def auth_put(path, body)
    basic_authorize @site.username, 'abcde'
    put "/webdav/#{path}", body
  end

  def auth_get(path)
    basic_authorize @site.username, 'abcde'
    get "/webdav/#{path}"
  end

  def auth_head(path)
    basic_authorize @site.username, 'abcde'
    head "/webdav/#{path}"
  end

  def auth_propfind(path, depth='1')
    basic_authorize @site.username, 'abcde'
    header 'Depth', depth
    request "/webdav/#{path}", method: 'PROPFIND'
    header 'Depth', nil
  end

  def auth_mkcol(path)
    basic_authorize @site.username, 'abcde'
    request "/webdav/#{path}", method: 'MKCOL'
  end

  def auth_delete(path)
    basic_authorize @site.username, 'abcde'
    delete "/webdav/#{path}"
  end

  def auth_move(from_path, to_path)
    basic_authorize @site.username, 'abcde'
    header 'Destination', "http://example.org/webdav/#{to_path}"
    request "/webdav/#{from_path}", method: 'MOVE'
    header 'Destination', nil
  end

  it 'creates files via PUT' do
    auth_put 'create.txt', 'hello webdav'
    _(last_response.status).must_equal 201
    _(Site[@site.id].file_exists?('create.txt')).must_equal true
  end

  it 'decodes percent-encoded paths when storing files' do
    encoded_path = 'Alien%20%281%29.jpg'
    decoded_path = 'Alien (1).jpg'

    auth_put encoded_path, 'image data'
    _(last_response.status).must_equal 201

    site = Site[@site.id]
    _(site.file_exists?(decoded_path)).must_equal true
    _(site.site_files_dataset.where(path: decoded_path).count).must_equal 1
    _(site.site_files_dataset.where(path: encoded_path).count).must_equal 0
  end

  it 'reads files via GET' do
    auth_put 'read.txt', 'read me'
    auth_get 'read.txt'
    _(last_response.status).must_equal 200
    _(last_response.body).must_equal 'read me'
  end

  it 'provides metadata via HEAD without a body' do
    auth_put 'meta.txt', 'meta'

    auth_head 'meta.txt'
    _(last_response.status).must_equal 200
    _(last_response.body).must_equal ''
    _(last_response.headers['Content-Length']).wont_be_nil
    _(last_response.headers['Content-Type']).must_equal 'text/plain'
    site_file = Site[@site.id].site_files_dataset.where(path: 'meta.txt').first
    _(site_file).wont_be_nil
    header_time = Time.httpdate(last_response.headers['Last-Modified'])
    _(header_time.to_i).must_equal site_file.updated_at.to_i
  end

  it 'updates files via MOVE' do
    auth_put 'update.txt', 'content'
    auth_move 'update.txt', 'renamed.txt'
    _(last_response.status).must_equal 201
    site = Site[@site.id]
    _(site.file_exists?('update.txt')).must_equal false
    _(site.file_exists?('renamed.txt')).must_equal true
  end

  it 'fails MOVE when destination header is empty' do
    auth_put 'move.txt', 'body'
    basic_authorize @site.username, 'abcde'
    header 'Destination', ''
    request '/webdav/move.txt', method: 'MOVE'
    header 'Destination', nil
    _(last_response.status).must_equal 400
  end

  it 'deletes files via DELETE' do
    auth_put 'delete.txt', 'gone'
    auth_delete 'delete.txt'
    _(last_response.status).must_equal 201
    _(Site[@site.id].file_exists?('delete.txt')).must_equal false
  end

  it 'rejects GET requests for directories' do
    auth_mkcol 'dir'
    auth_get 'dir'
    _(last_response.status).must_equal 403
    _(last_response.body).must_include 'directory'
  end

  it 'rejects DELETE of index.html' do
    auth_put 'index.html', 'index'
    auth_delete 'index.html'
    _(last_response.status).must_equal 403
    _(last_response.body).must_include 'index.html'
  end

  it 'prevents PUT when a directory exists at the path' do
    auth_mkcol 'dup'
    auth_put 'dup', 'nope'
    _(last_response.status).must_equal 409
    _(last_response.body).must_include 'conflicts with an existing directory'
  end

  it 'rejects MKCOL with invalid paths' do
    auth_mkcol '../bad'
    _(last_response.status).must_equal 400
    _(last_response.body).must_include 'Invalid path'
  end

  it 'returns 401 for unauthenticated requests' do
    get '/webdav/test.txt'
    _(last_response.status).must_equal 401
    _(last_response.headers['WWW-Authenticate']).must_include 'Basic'
  end

  it 'requires supporter accounts' do
    free_site = Fabricate(:site)
    free_site.update(plan_type: 'free')
    basic_authorize free_site.username, 'abcde'
    get '/webdav/test.txt'
    _(last_response.status).must_equal 402
    _(last_response.headers['X-Upgrade-Required']).must_include 'supporter'
  end

  it 'lists resources with PROPFIND depth 0 on root' do
    auth_propfind '', '0'
    _(last_response.status).must_equal 207
    doc = Nokogiri::XML(last_response.body)
    hrefs = doc.xpath('//D:href', 'D' => 'DAV:').map(&:text)
    _(hrefs).must_include('/webdav/')
  end

  it 'lists children with PROPFIND depth 1' do
    auth_mkcol 'folder'
    auth_put 'folder/file.txt', 'data'

    auth_propfind 'folder', '1'
    _(last_response.status).must_equal 207
    doc = Nokogiri::XML(last_response.body)
    hrefs = doc.xpath('//D:href', 'D' => 'DAV:').map(&:text)
    _(hrefs).must_include('/webdav/folder/')
    _(hrefs).must_include('/webdav/folder/file.txt')
  end

  it 'returns 404 for PROPFIND on missing paths' do
    auth_propfind 'missing.txt', '0'
    _(last_response.status).must_equal 404
  end
end
