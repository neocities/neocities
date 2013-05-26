require './environment.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

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
    DB.transaction { @site.save }

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