require 'rubygems'
require './app.rb'
require 'sidekiq/web'

map('/') { run Sinatra::Application }

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

      if Site.valid_file_type?(filename: path, tempfile: tmpfile)
        site.store_file path, tmpfile
        return [201, {}, ['']]
      else
        return [415, {}, ['']]
      end
    end

    if env['REQUEST_METHOD'] == 'MOVE'
      tmpfile = Tempfile.new 'moved_file'
      tmpfile.close

      destination = env['HTTP_DESTINATION'].match(/^.+\/webdav(.+)$/i).captures.first

      FileUtils.cp site.files_path(env['PATH_INFO']), tmpfile.path

      DB.transaction do
        site.store_file destination, tmpfile
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

  run Sidekiq::Web
end