require './environment.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

get %r{.+} do
  subname = request.host.match /[\w-]+/
  pass if subname.nil?  
  subname = subname.to_s
  pass if subname == 'www' || subname == 'neocities' || subname == 'testneocities'

  base_path = site_base_path subname
  path = File.join(base_path, (request.path =~ /\/$/ ? (request.path + 'index.html') : request.path))

  if File.exist?(path)
    send_file path
  else
    send_file File.join(base_path, 'not_found.html')
  end

  send_file path
end

get '/' do
  dashboard_if_signed_in
  slim :index
end

get '/new' do
  dashboard_if_signed_in
  @site = Site.new
  slim :'new'
end

get '/dashboard' do
  slim :'dashboard'
end

get '/signin' do
  dashboard_if_signed_in
  slim :'signin'
end

post '/create' do
  dashboard_if_signed_in
  @site = Site.new username: params[:username], password: params[:password], email: params[:email], new_tags: params[:tags]

  if @site.valid?
    
    base_path = site_base_path @site.username

    DB.transaction {
      @site.save

      begin
        FileUtils.mkdir base_path
      rescue Errno::EEXIST
      end

      File.write File.join(base_path, 'index.html'), slim(:'templates/index', pretty: true, layout: false)
      File.write File.join(base_path, 'not_found.html'), slim(:'templates/not_found', pretty: true, layout: false)
    }

    session[:id] = @site.id
    redirect '/dashboard'
  else
    slim :'/new'
  end
end

post '/signin' do
  dashboard_if_signed_in
  if Site.valid_login? params[:username], params[:password]
    site = Site[username: params[:username]]
    session[:id] = site.id
    redirect '/dashboard'
  else
    flash[:error] = 'Invalid login.'
    redirect '/signin'
  end
end

get '/signout' do
  require_login
  session[:id] = nil
  redirect '/'
end

def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def require_login
  redirect '/' unless signed_in?
end

def signed_in?
  !session[:id].nil?
end

def current_site
  @site ||= Site[id: session[:id]]
end

def site_base_path(subname)
  File.join settings.public_folder, 'sites', subname
end

def template_site_title(username)
  "#{username.capitalize}#{username[username.length-1] == 's' ? "'" : "'s"} Site"
end