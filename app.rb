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

get '/?' do
  dashboard_if_signed_in
  slim :index
end

get '/browse' do
  @current_page = params[:current_page] || 1
  @current_page = @current_page.to_i
  site_dataset = Site.order(:updated_at.desc, :hits.desc).filter(is_banned: false).filter(~{updated_at: nil}).paginate(@current_page, 201)
  @page_count = site_dataset.page_count || 1
  @sites = site_dataset.all
  slim :browse
end

get '/new' do
  dashboard_if_signed_in
  @site = Site.new
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

post '/create' do
  dashboard_if_signed_in
  @site = Site.new username: params[:username], password: params[:password], email: params[:email], new_tags: params[:tags]

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

get '/site_files/new' do
  require_login
  slim :'site_files/new'
end

get '/about' do
  slim :'about'
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

  unless Site::VALID_MIME_TYPES.include?(mime_type) && Site::VALID_EXTENSIONS.include?(File.extname(params[:newfile][:filename]).sub(/^./, ''))
    @errors << 'File must me one of the following: HTML, Text, Image (JPG PNG GIF JPEG SVG), JS, CSS, Markdown.'
    halt slim(:'site_files/new')
  end

  sanitized_filename = params[:newfile][:filename].gsub(/[^a-zA-Z0-9_\-.]/, '')

  dest_path = File.join(site_base_path(current_site.username), sanitized_filename)
  FileUtils.mv params[:newfile][:tempfile].path, dest_path
  File.chmod(0640, dest_path) if self.class.production?

  Backburner.enqueue(ScreenshotJob, current_site.username) if sanitized_filename =~ /index\.html/

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

  sanitized_filename = filename.gsub(/[^a-zA-Z_\-.]/, '')
  dest_path = File.join site_base_path(current_site.username), sanitized_filename

  FileUtils.mv tmpfile.path, dest_path
  File.chmod(0640, dest_path) if self.class.production?

  Backburner.enqueue(ScreenshotJob, current_site.username) if sanitized_filename =~ /index\.html/

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
  @banned_sites = Site.filter(is_banned: true).order(:username).all
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
    site.save(validate: false)
  }

  flash[:success] = 'MISSION ACCOMPLISHED'
  redirect '/admin'
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
