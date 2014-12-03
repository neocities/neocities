get '/dashboard' do
  require_login

  if params[:dir] && params[:dir][0] != '/'
    params[:dir] = '/'+params[:dir]
  end

  if !File.directory?(current_site.files_path(params[:dir]))
    redirect '/dashboard'
  end

  @dir = params[:dir]
  @file_list = current_site.file_list @dir
  erb :'dashboard'
end