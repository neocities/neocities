require 'rubygems'
require './app.rb'
require 'sidekiq/web'
require 'airbrake/sidekiq'

use Airbrake::Rack::Middleware

map('/') do
  use(Rack::Cache,
    verbose: false,
    metastore: 'file:/tmp/neocitiesrackcache/meta',
    entitystore: 'file:/tmp/neocitiesrackcache/body'
  )
  run Sinatra::Application
end

map '/webdav' do
  use Rack::Auth::Basic do |username, password|
    @site = Site.get_site_from_login(username, password)
    @site ? true : false
  end

  run lambda { |env|
    request_method = env['REQUEST_METHOD']
    path = env['PATH_INFO']

    case request_method
    when 'OPTIONS'
      return [200, {'Allow' => 'OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, MKCOL, MOVE', 'DAV' => '1,2'}, ['']]

    when 'PUT'
      tmpfile = Tempfile.new('davfile', encoding: 'binary')
      tmpfile.write(env['rack.input'].read)
      tmpfile.close

      return [507, {}, ['']] if @site.file_size_too_large?(tmpfile.size)

      if @site.okay_to_upload?(filename: path, tempfile: tmpfile)
        @site.store_files([{ filename: path, tempfile: tmpfile }])
        return [201, {}, ['']]
      else
        return [415, {}, ['']]
      end

    when 'MKCOL'
      @site.create_directory(path)
      return [201, {}, ['']]

    when 'MOVE'
      destination = env['HTTP_DESTINATION'][/\/webdav(.+)$/i, 1]
      return [400, {}, ['Bad Request']] unless destination

      path.sub!(/^\//, '') # Remove leading slash if present
      site_file = @site.site_files.find { |s| s.path == path }
      return [404, {}, ['']] unless site_file

      site_file.rename(destination)
      return [201, {}, ['']]

    when 'DELETE'
      @site.delete_file(path)
      return [201, {}, ['']]

    else
      unless ['PROPFIND', 'GET', 'HEAD'].include? request_method
        return [501, {}, ['Not Implemented']]
      end

      env['PATH_INFO'] = "/#{@site.scrubbed_path(path)}" unless path.empty?

      DAV4Rack::Handler.new(
        root: @site.files_path,
        root_uri_path: '/webdav'
      ).call(env)
    end
  }
end

map '/sidekiq' do
  use Rack::Auth::Basic, "Protected Area" do |username, password|
    raise 'missing sidekiq auth' unless $config['sidekiq_user'] && $config['sidekiq_pass']
    username == $config['sidekiq_user'] && password == $config['sidekiq_pass']
  end

  use Rack::Session::Cookie, key: 'sidekiq.session', secret: Base64.strict_decode64($config['session_secret'])
  use Rack::Protection::AuthenticityToken
  run Sidekiq::Web
end
