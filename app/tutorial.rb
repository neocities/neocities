def default_tutorial_html
  <<-EOT.strip
<!DOCTYPE html>
<html>
  <body>


    Hello World!


  </body>
</html>
EOT
end

get '/tutorials' do
  erb :'tutorials'
end

get '/tutorial/?' do
  require_login
  erb :'tutorial/index'
end

get '/tutorial/:section/?' do
  require_login
  redirect "/tutorial/#{params[:section]}/1"
end

get '/tutorial/:section/:page/?' do
  require_login
  @page = params[:page]
  not_found if @page.to_i == 0
  not_found unless %w{html css js}.include?(params[:section])

  @section = params[:section]

  @title = "#{params[:section].upcase} Tutorial - #{@page}/10"

  erb "tutorial/layout".to_sym
end
