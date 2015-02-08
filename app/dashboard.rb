get '/dashboard' do
  require_login
  dashboard_init
  erb :'dashboard'
end

def dashboard_init
  if params[:dir] && params[:dir][0] != '/'
    params[:dir] = '/'+params[:dir]
  end

  if !File.directory?(current_site.files_path(params[:dir]))
    if !File.directory?(current_site.files_path)
      flash[:error] = 'Could not find your web site, please contact support.'
      signout
      redirect '/'
    else
      flash[:error] = 'Could not find the requested directory.'
      redirect '/dashboard'
    end
  end

  @dir = params[:dir]
  @file_list = current_site.file_list @dir
end