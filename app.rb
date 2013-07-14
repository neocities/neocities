require './environment.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

use Rack::Recaptcha, public_key: $config['recaptcha_public_key'], private_key: $config['recaptcha_private_key']
helpers Rack::Recaptcha::Helpers

before do
  redirect '/' if request.post? && !csrf_safe?
end

not_found do
  slim :'not_found'
end

error do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[NeoCities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: "#{request.request_method} #{request.path}\n\n" +
          (current_site ? "Site: #{current_site.username}\nEmail: #{current_site.email}\n\n" : '') +
          env['sinatra.error'].backtrace.join("\n")
  })

  slim :'error'
end

get '/?' do
  dashboard_if_signed_in
  erb :index, layout: false
end

get '/browse' do
  @current_page = params[:current_page] || 1
  @current_page = @current_page.to_i
  site_dataset = Site.order(:updated_at.desc, :hits.desc).filter(is_banned: false).filter(~{updated_at: nil}).paginate(@current_page, 201)

  site_dataset.filter! is_nsfw: (!params[:is_nsfw].nil? ? true : false)

  @page_count = site_dataset.page_count || 1
  @sites = site_dataset.all
  erb :browse
end

get '/tutorials' do
  erb :'tutorials'
end

get '/donate' do
  erb :'donate'
end

get '/blog' do
  # expires 500, :public, :must_revalidate
  return File.read File.join(DIR_ROOT, 'public', 'sites', 'blog', 'index.html')
end

get '/blog/:article' do |article|
  # expires 500, :public, :must_revalidate
  return File.read File.join(DIR_ROOT, 'public', 'sites', 'blog', "#{article}.html")
end

get '/new' do
  dashboard_if_signed_in
  @site = Site.new username: params[:username]
  slim :'new'
end

get '/dashboard' do
  require_login
  slim :'dashboard'
end

get '/signin' do
  dashboard_if_signed_in
  slim :'signin'
end

get '/settings' do
  require_login
  slim :'settings'
end

post '/create' do
  dashboard_if_signed_in
  @site = Site.new username: params[:username], password: params[:password], email: params[:email], new_tags: params[:tags], is_nsfw: params[:is_nsfw], ip: request.ip

  recaptcha_is_valid = recaptcha_valid?

  if @site.valid? && recaptcha_is_valid

    base_path = site_base_path @site.username

    DB.transaction {
      @site.save

      FileUtils.mkdir base_path

      File.write File.join(base_path, 'index.html'), slim(:'templates/index', pretty: true, layout: false)
      File.write File.join(base_path, 'not_found.html'), slim(:'templates/not_found', pretty: true, layout: false)
    }

    session[:id] = @site.id
    redirect '/dashboard'
  else
    @site.errors.add :captcha, 'You must type in the two words correctly! Try again.' if !recaptcha_is_valid

    slim :'/new'
  end
end

post '/signin' do
  dashboard_if_signed_in
  if Site.valid_login? params[:username], params[:password]
    site = Site[username: params[:username]]

    if site.is_banned
      flash[:error] = 'Invalid login.'
      redirect '/signin'
    end

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

get '/about' do
  erb :'about'
end

get '/site_files/new_page' do
  require_login
  slim :'site_files/new_page'
end

post '/change_password' do
  require_login

  if !Site.valid_login?(current_site.username, params[:current_password])
    current_site.errors.add :password, 'Your provided password does not match the current one.'
    halt slim(:'settings')
  end

  current_site.password = params[:new_password]
  current_site.valid?

  if params[:new_password] != params[:new_password_confirm]
    current_site.errors.add :password, 'New passwords do not match.'
  end

  if current_site.errors.empty?
    current_site.save
    flash[:success] = 'Successfully changed password.'
    redirect '/settings'
  else
    halt slim(:'settings')
  end
end

post '/change_name' do
  require_login
  current_username = current_site.username
  
  if current_site.username == params[:name]
    flash[:error] = 'You already have this name.'
    redirect '/settings'
  end
  
  current_site.username = params[:name]
  
  if current_site.valid?
    DB.transaction {
      current_site.save
      FileUtils.mv site_base_path(current_username), site_base_path(current_site.username)
    }
    
    flash[:success] = "Site/user name has been changed. You will need to use this name to login, <b>don't forget it</b>."
    redirect '/settings'
  else
    halt slim(:'settings')
  end
end

post '/change_nsfw' do
  require_login
  current_site.update is_nsfw: params[:is_nsfw]
  redirect '/settings'
end

post '/site_files/create_page' do
  require_login
  @errors = []

  params[:pagefilename].gsub!(/[^a-zA-Z0-9_\-.]/, '')
  params[:pagefilename].gsub!(/\.html$/i, '')

  if params[:pagefilename].nil? || params[:pagefilename].empty?
    @errors << 'You must provide a file name.'
    halt slim(:'site_files/new_page')
  end

  name = "#{params[:pagefilename]}.html"
  path = site_file_path name

  if File.exist? path
    @errors << %{Web page "#{name}" already exists! Choose another name.}
    halt slim(:'site_files/new_page')
  end

  File.write path, slim(:'templates/index', pretty: true, layout: false)

  flash[:success] = %{#{name} was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/#{name}">Click here to edit it</a>.}

  redirect '/dashboard'
end

get '/site_files/new' do
  require_login
  slim :'site_files/new'
end

post '/site_files/upload' do
  require_login
  @errors = []

  if params[:newfile] == '' || params[:newfile].nil?
    @errors << 'You must select a file to upload.'
    halt slim(:'site_files/new')
  end

  if params[:newfile][:tempfile].size > Site::MAX_SPACE || (params[:newfile][:tempfile].size + current_site.total_space) > Site::MAX_SPACE
    @errors << 'File size must be smaller than available space.'
    halt slim(:'site_files/new')
  end

  mime_type = Magic.guess_file_mime_type params[:newfile][:tempfile].path

  unless (Site::VALID_MIME_TYPES.include?(mime_type) || mime_type =~ /text/) && Site::VALID_EXTENSIONS.include?(File.extname(params[:newfile][:filename]).sub(/^./, ''))
    @errors << 'File must me one of the following: HTML, Text, Image (JPG PNG GIF JPEG SVG), JS, CSS, Markdown.'
    halt slim(:'site_files/new')
  end

  sanitized_filename = params[:newfile][:filename].gsub(/[^a-zA-Z0-9_\-.]/, '')

  dest_path = File.join(site_base_path(current_site.username), sanitized_filename)
  FileUtils.mv params[:newfile][:tempfile].path, dest_path
  File.chmod(0640, dest_path) if self.class.production?

  ScreenshotWorker.perform_async(current_site.username) if sanitized_filename =~ /index\.html/

  current_site.update updated_at: Time.now

  flash[:success] = "Successfully uploaded file #{sanitized_filename}."
  redirect '/dashboard'
end

post '/site_files/delete' do
  require_login
  sanitized_filename = params[:filename].gsub(/[^a-zA-Z0-9_\-.]/, '')
  FileUtils.rm File.join(site_base_path(current_site.username), sanitized_filename)
  flash[:success] = "Deleted file #{params[:filename]}."
  redirect '/dashboard'
end

get '/site_files/:username.zip' do |username|
  require_login
  file_path = "/tmp/neocities-site-#{username}.zip"

  Zip::ZipFile.open(file_path, Zip::ZipFile::CREATE) do |zipfile|
    current_site.file_list.collect {|f| f.filename}.each do |filename|
      zipfile.add filename, site_file_path(filename)
    end
  end

  # I don't want to have to deal with cleaning up old tmpfiles
  zipfile = File.read file_path
  File.delete file_path

  content_type 'application/octet-stream'
  attachment   "#{current_site.username}.zip"

  return zipfile
end

get '/site_files/download/:filename' do |filename|
  require_login
  send_file File.join(site_base_path(current_site.username), filename), filename: filename, type: 'Application/octet-stream'
end

get '/site_files/text_editor/:filename' do |filename|
  require_login
  @file_data = File.read File.join(site_base_path(current_site.username), filename)
  slim :'site_files/text_editor'
end

post '/site_files/save/:filename' do |filename|
  require_login_ajax

  tmpfile = Tempfile.new 'neocities_saving_file'

  if (tmpfile.size + current_site.total_space) > Site::MAX_SPACE
    halt 'File is too large to fit in your space, it has NOT been saved. Please make a local copy and then try to reduce the size.'
  end

  input = request.body.read
  tmpfile.set_encoding input.encoding
  tmpfile.write input
  tmpfile.close

  sanitized_filename = filename.gsub(/[^a-zA-Z0-9_\-.]/, '')
  dest_path = File.join site_base_path(current_site.username), sanitized_filename

  FileUtils.mv tmpfile.path, dest_path
  File.chmod(0640, dest_path) if self.class.production?

  ScreenshotWorker.perform_async(current_site.username) if sanitized_filename =~ /index\.html/

  current_site.update updated_at: Time.now

  'ok'
end

get '/terms' do
  slim :'terms'
end

get '/privacy' do
  slim :'privacy'
end

get '/admin' do
  require_admin
  @banned_sites = Site.select(:username).filter(is_banned: true).order(:username).all
  @nsfw_sites = Site.select(:username).filter(is_nsfw: true).order(:username).all
  slim :'admin'
end

post '/admin/banhammer' do
  require_admin
  site = Site[username: params[:username]]

  if site.is_banned
    flash[:error] = 'User is already banned'
    redirect '/admin'
  end

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  DB.transaction {
    FileUtils.mv site_base_path(site.username), File.join(settings.public_folder, 'banned_sites', site.username)
    site.is_banned = true
    site.save validate: false
  }

  if !['127.0.0.1', nil, ''].include? site.ip
    `sudo ufw insert 1 deny from #{site.ip}`
  end

  flash[:success] = 'MISSION ACCOMPLISHED'
  redirect '/admin'
end

post '/admin/mark_nsfw' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  site.is_nsfw = true
  site.save validate: false

  flash[:success] = 'MISSION ACCOMPLISHED'
  redirect '/admin'
end

get '/password_reset' do
  slim :'password_reset'
end

post '/send_password_reset' do
  site = Site[email: params[:email]]

  if site
    token = SecureRandom.uuid.gsub('-', '')
    site.update password_reset_token: token

    body = <<-EOT
Hello! This is the NeoCities cat, and I have received a password reset request for your e-mail address. Purrrr.

Go to this URL to reset your password: http://neocities.org/password_reset_confirm?code=#{token}

If you didn't request this reset, you can ignore it. Or hide under a bed. Or take a nap. Your call.

Meow,
the NeoCities Cat
    EOT

    body.strip!

    EmailWorker.perform_async({
      from: 'web@neocities.org',
      to: params[:email],
      subject: '[NeoCities] Password Reset',
      body: body
    })
  end

  flash[:success] = 'If your email was valid (and used by a site), the NeoCities Cat will send an e-mail to your account with password reset instructions.'
  redirect '/'
end

get '/password_reset_confirm' do
  site = Site[password_reset_token: params[:code]]

  if site
    site.password = params[:code]
    site.save

    flash[:success] = 'Your password has been changed to the token sent in your e-mail. Please login and change your password in the settings page as soon as possible.'
  else
    flash[:error] = 'Could not find a site with this token.'
  end
  
  redirect '/'
end

get '/contact' do
  slim :'contact'
end

post '/contact' do
  
  @errors = []
  
  if params[:email].empty? || params[:subject].empty? || params[:body].empty?
    @errors << 'Please fill out all fields'
  end
  
  if !recaptcha_valid?
    @errors << 'Captcha was not filled out (or was filled out incorrectly)'
  end
  
  if !@errors.empty?
    slim :'contact'
  else
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      reply_to: params[:email],
      to: 'contact@neocities.org',
      subject: "[NeoCities Contact]: #{params[:subject]}",
      body: params[:body]
    })
    
    flash[:success] = 'Your contact has been sent.'
    redirect '/'
  end
end

def require_admin
  redirect '/' unless signed_in? && current_site.is_admin
end

def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def require_login_ajax
  halt 'You are not logged in!' unless signed_in?
end

def csrf_safe?
  csrf_token == params[:csrf_token] || csrf_token == request.env['HTTP_X_CSRF_TOKEN']
end

def csrf_token
   session[:_csrf_token] ||= SecureRandom.base64(32)
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

def site_file_path(filename)
  File.join(site_base_path(current_site.username), filename)
end

def template_site_title(username)
  "#{username.capitalize}#{username[username.length-1] == 's' ? "'" : "'s"} Site"
end
