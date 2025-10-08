require 'rubygems'
require './app.rb'
require 'sidekiq/web'
require 'airbrake/sidekiq'
require 'dav4rack'
require 'dav4rack/resources/file_resource'

use Airbrake::Rack::Middleware

map('/') do
  run Sinatra::Application
end

map '/webdav' do
  # Custom resource class to prevent .attrib_store file creation
  class NeocitiesWebDAVResource < DAV4Rack::FileResource
    def custom_props(element)
      {}
    end

    def set_property(name, value)
      true
    end

    def remove_property(element)
      true
    end
  end

  use Rack::Auth::Basic do |username, password|
    @site = Site.get_site_from_login(username, password)
    @site ? true : false
  end

  run lambda { |env|
    request_method = env['REQUEST_METHOD']
    path = env['PATH_INFO']

    unless @site.owner.supporter?
      return [
        402,
        {
          'Content-Type' => 'application/xml',
          'X-Upgrade-Required' => 'https://neocities.org/supporter'
        },
        [
          <<~XML
            <?xml version="1.0" encoding="utf-8"?>
            <error xmlns="DAV:">
              <message>WebDAV access requires a supporter account.</message>
            </error>
          XML
        ]
      ]
    end

    case request_method
    when 'OPTIONS'
      return [200, {'Allow' => 'OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, MKCOL, MOVE', 'DAV' => '1,2'}, ['']]

    when 'PUT'
      tmpfile = Tempfile.new('davfile', encoding: 'binary')
      tmpfile.write(env['rack.input'].read)
      tmpfile.close

      result = @site.store_files([{ filename: path, tempfile: tmpfile }])

      if result.is_a?(Hash) && result[:error]
        # Map error types to appropriate HTTP status codes
        status_code = case result[:error_type]
        when 'too_large', 'file_too_large', 'too_many_files'
          507  # Insufficient Storage
        when 'directory_exists'
          409  # Conflict
        when 'invalid_file_type'
          415  # Unsupported Media Type
        else
          400  # Bad Request
        end
        return [status_code, {}, [result[:message]]]
      end

      return [201, {}, ['']]

    when 'MKCOL'
      return [400, {}, ['Invalid path']] if @site.invalid_path?(path)
      return [400, {}, ['Path too long']] if SiteFile.path_too_long?(path)
      return [409, {}, ['Already exists']] if @site.file_exists?(path)

      @site.create_directory(path)
      return [201, {}, ['']]

    when 'MOVE'
      destination = env['HTTP_DESTINATION'][/\/webdav(.+)$/i, 1]
      return [400, {}, ['Bad Request']] unless destination

      path.sub!(/^\//, '') # Remove leading slash if present
      site_file = @site.site_files.find { |s| s.path == path }
      return [404, {}, ['']] unless site_file

      return [400, {}, ['Invalid destination path']] if @site.invalid_path?(destination)
      return [400, {}, ['Destination path too long']] if SiteFile.path_too_long?(destination)
      return [400, {}, ['Destination filename too long']] if SiteFile.name_too_long?(destination)
      return [403, {}, ['Cannot rename to index.html at root']] if destination == '/index.html' && path != '/index.html'

      res = site_file.rename(destination)
      if res.first == true
        return [201, {}, ['']]
      else
        return [400, {}, [res.last]]
      end

    when 'DELETE'
      return [403, {}, ['Cannot delete index.html']] if path == '/index.html' || path == 'index.html'
      return [403, {}, ['Cannot delete root directory']] if @site.files_path(path) == @site.files_path
      return [404, {}, ['File not found']] unless @site.file_exists?(path)

      @site.delete_file(path)
      return [201, {}, ['']]
    else
      unless ['PROPFIND', 'GET', 'HEAD'].include? request_method
        return [501, {}, ['Not Implemented']]
      end

      env['PATH_INFO'] = "/#{@site.scrubbed_path(path)}" unless path.empty?

      # Terrible hack to fix WebDAV for the VSC plugin
      if env['CONTENT_LENGTH'] == "0"
        env['rack.input'] = StringIO.new('<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:"><prop>
<getcontentlength xmlns="DAV:"/>
<getlastmodified xmlns="DAV:"/>
<resourcetype xmlns="DAV:"/>
</prop></propfind>')
        env['CONTENT_LENGTH'] = env['rack.input'].length.to_s
      end

      DAV4Rack::Handler.new(
        root: @site.files_path,
        root_uri_path: '/webdav',
        resource_class: NeocitiesWebDAVResource
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
