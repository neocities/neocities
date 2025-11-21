require 'rubygems'
require './app.rb'
require 'sidekiq/web'
require 'airbrake/sidekiq'
require 'rack/mime'
require 'rack/utils'
require 'time'

use Airbrake::Rack::Middleware

map('/') do
  run Sinatra::Application
end

map '/webdav' do
  use Rack::Auth::Basic do |username, password|
    @site = Site.get_site_from_login(username, password)
    @site ? true : false
  end

  run lambda { |env|
    request_method = env['REQUEST_METHOD']
    begin
      path = Rack::Utils.unescape_path(env['PATH_INFO'])
    rescue ArgumentError
      return [400, {}, ['Invalid path']]
    end

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

    when 'GET', 'HEAD'
      begin
        scrubbed_path = @site.scrubbed_path(path)
      rescue ArgumentError
        return [400, {}, ['Invalid path']]
      end

      if scrubbed_path.empty? || @site.is_directory?(scrubbed_path)
        return [403, {}, ['Cannot download a directory']]
      end

      return [404, {}, ['']] unless @site.file_exists?(scrubbed_path)

      site_file = @site.site_files_dataset.where(path: scrubbed_path).first
      file_path = @site.files_path(scrubbed_path)

      begin
        file_stat = File.stat(file_path)
      rescue Errno::ENOENT
        return [404, {}, ['']]
      end

      content_length = site_file&.size || file_stat.size
      last_modified =
        if site_file&.updated_at
          site_file.updated_at
        elsif site_file&.created_at
          site_file.created_at
        else
          file_stat.mtime
        end

      headers = {
        'Content-Type' => Rack::Mime.mime_type(File.extname(scrubbed_path), 'application/octet-stream'),
        'Content-Length' => content_length.to_s,
        'Last-Modified' => last_modified.httpdate
      }

      if request_method == 'HEAD'
        return [200, headers, []]
      end

      file_io = File.open(file_path, 'rb')
      return [200, headers, file_io]

    when 'PROPFIND'
      begin
        scrubbed_path = @site.scrubbed_path(path)
      rescue ArgumentError
        return [400, {}, ['Invalid path']]
      end

      target_is_root = scrubbed_path.empty?

      site_file =
        unless target_is_root
          @site.site_files_dataset.where(path: scrubbed_path).first
        end

      if !target_is_root && site_file.nil?
        return [404, {}, ['']]
      end

      if site_file && !site_file.is_directory && !@site.file_exists?(scrubbed_path)
        return [404, {}, ['']]
      end

      depth_header = env['HTTP_DEPTH']
      depth = depth_header == '0' ? 0 : 1

      responses = []

      build_response_info = lambda do |relative_path, file_info|
        is_directory = file_info[:is_directory]
        href_path_segments = relative_path.split('/').reject(&:empty?).map { |segment| Rack::Utils.escape_path(segment) }
        href = '/webdav'
        href += '/' unless href_path_segments.empty?
        href += href_path_segments.join('/')
        href += '/' if is_directory && !href.end_with?('/')

        display_name =
          if relative_path.empty?
            '/'
          else
            relative_path.split('/').last
          end

        updated_at = file_info[:updated_at] || file_info[:created_at]

        <<~XML
          <D:response>
            <D:href>#{Rack::Utils.escape_html(href)}</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>#{Rack::Utils.escape_html(display_name)}</D:displayname>
                <D:resourcetype>#{is_directory ? '<D:collection/>' : ''}</D:resourcetype>
                #{file_info[:created_at] ? "<D:creationdate>#{file_info[:created_at].utc.iso8601}</D:creationdate>" : ''}
                #{updated_at ? "<D:getlastmodified>#{updated_at.httpdate}</D:getlastmodified>" : ''}
                #{is_directory ? '' : "<D:getcontentlength>#{file_info[:size]}</D:getcontentlength>"}
                #{file_info[:content_type] ? "<D:getcontenttype>#{Rack::Utils.escape_html(file_info[:content_type])}</D:getcontenttype>" : ''}
                #{file_info[:etag] ? "<D:getetag>#{Rack::Utils.escape_html(file_info[:etag])}</D:getetag>" : ''}
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        XML
      end

      add_response_for = lambda do |relative_path, file_info|
        responses << build_response_info.call(relative_path, file_info)
      end

      target_info =
        if target_is_root
          {
            is_directory: true,
            size: 0,
            created_at: @site.created_at,
            updated_at: @site.site_updated_at || @site.updated_at,
            content_type: nil,
            etag: nil
          }
        else
          {
            is_directory: site_file.is_directory,
            size: site_file.is_directory ? 0 : site_file.size.to_i,
            created_at: site_file.created_at,
            updated_at: site_file.updated_at,
            content_type: site_file.is_directory ? nil : Rack::Mime.mime_type(File.extname(scrubbed_path), 'application/octet-stream'),
            etag: site_file.sha1_hash ? %("#{site_file.sha1_hash}") : nil
          }
        end

      add_response_for.call(scrubbed_path, target_info)

      if depth > 0 && (target_is_root || target_info[:is_directory])
        @site.file_list(scrubbed_path).each do |entry|
          child_info = {
            is_directory: entry[:is_directory],
            size: entry[:is_directory] ? 0 : entry[:size].to_i,
            created_at: entry[:created_at],
            updated_at: entry[:updated_at],
            content_type: entry[:is_directory] ? nil : Rack::Mime.mime_type(File.extname(entry[:path]), 'application/octet-stream'),
            etag: entry[:sha1_hash] ? %("#{entry[:sha1_hash]}") : nil
          }

          add_response_for.call(entry[:path], child_info)
        end
      end

      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          #{responses.join}
        </D:multistatus>
      XML

      return [207, {'Content-Type' => 'application/xml; charset=utf-8', 'DAV' => '1,2'}, [xml]]

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

      begin
        destination = Rack::Utils.unescape_path(destination)
      rescue ArgumentError
        return [400, {}, ['Invalid destination path']]
      end

      # Remove leading and trailing slashes if present
      path.sub!(/^\//, '')
      path.sub!(/\/$/, '')
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
      return [501, {}, ['Not Implemented']]
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
