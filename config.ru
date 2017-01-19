require 'rubygems'
require './app.rb'
require 'sidekiq/web'

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
    Site.valid_login? username, password
  end

  run lambda {|env|
    site = Site[username: env['REMOTE_USER']]

    if env['REQUEST_METHOD'] == 'PUT'
      path = env['PATH_INFO']
      tmpfile = Tempfile.new 'davfile', encoding: 'binary'
      tmpfile.write env['rack.input'].read
      tmpfile.close

      if site.file_size_too_large? tmpfile.size
        return [507, {}, ['']]
      end

      # if Site.valid_file_type?(filename: path, tempfile: tmpfile)
      if site.okay_to_upload? filename: path, tempfile: tmpfile
        site.store_files [{filename: path, tempfile: tmpfile}]
        return [201, {}, ['']]
      else
        return [415, {}, ['']]
      end
    end

    if env['REQUEST_METHOD'] == 'MKCOL'
      site.create_directory env['PATH_INFO']
      return [201, {}, ['']]
    end

    if env['REQUEST_METHOD'] == 'MOVE'
      tmpfile = Tempfile.new 'moved_file'
      tmpfile.close

      destination = env['HTTP_DESTINATION'].match(/^.+\/webdav(.+)$/i).captures.first

      FileUtils.cp site.files_path(env['PATH_INFO']), tmpfile.path

      DB.transaction do
        site.store_files [{filename: destination, tempfile: tmpfile}]
        site.delete_file env['PATH_INFO']
      end

      return [201, {}, ['']]
    end

    if env['REQUEST_METHOD'] == 'DELETE'
      site.delete_file env['PATH_INFO']
      return [201, {}, ['']]
    end

    res = DAV4Rack::Handler.new(
      root: Site.select(:username).where(username: env['REMOTE_USER']).first.files_path,
      root_uri_path: '/webdav'
    ).call(env)
  }
end

map '/sidekiq' do
  use Rack::Auth::Basic, "Protected Area" do |username, password|
    raise 'missing sidekiq auth' unless $config['sidekiq_user'] && $config['sidekiq_pass']
    username == $config['sidekiq_user'] && password == $config['sidekiq_pass']
  end

  use Rack::Session::Cookie, key: 'sidekiq.session', secret: $config['session_secret']
  use Rack::Protection::AuthenticityToken
  run Sidekiq::Web
end
