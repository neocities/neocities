require './environment.rb'

get '/' do
  slim :index
end

get '/new' do
  @site = Site.new
  slim :'new'
end

get '/dashboard' do
  slim :'dashboard'
end

post '/create' do
  @site = Site.new username: params[:username], password: params[:password], email: params[:email]
  if @site.valid?

    @server = Server.with_slots_available

    if @server.nil?
      raise 'no slots available'
    end

    @site.server = @server
    @site.save

    session[:username] = @site.username
    redirect '/dashboard'
  else
    slim :'/new'
  end
end

post '/signin' do
  if Site.valid_login? params[:username], params[:password]
    session[:username] = params[:username]
    redirect '/dashboard'
  else
    flash[:error] = 'Invalid login.'
    redirect '/'
  end
end

get '/signout' do
  require_login
  session[:username] = nil
  session[:timezone] = nil
  redirect '/'
end

def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def require_login
  redirect '/' unless signed_in?
end

def signed_in?
  !session[:username].nil?
end