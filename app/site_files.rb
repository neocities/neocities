get '/site_files/new_page' do
  require_login
  @title = 'New Page'
  erb :'site_files/new_page'
end

# Redirect from original path
get '/site_files/new' do
  require_login
  redirect '/site_files/new_page'
end

post '/site_files/create' do
  require_login
  @errors = []

  filename = params[:pagefilename] || params[:filename]

  filename.gsub!(/[^a-zA-Z0-9_\-.]/, '')

  redirect_uri = '/dashboard'
  redirect_uri += "?dir=#{Rack::Utils.escape params[:dir]}" if params[:dir]

  if filename.nil? || filename.strip.empty?
    flash[:error] = 'You must provide a file name.'
    redirect redirect_uri
  end

  name = "#{filename}"

  name = "#{params[:dir]}/#{name}" if params[:dir]

  name = current_site.scrubbed_path name

  if current_site.file_exists?(name)
    flash[:error] = %{Web page "#{Rack::Utils.escape_html name}" already exists! Choose another name.}
    redirect redirect_uri
  end

  extname = File.extname name

  unless extname.match /^\.#{Site::EDITABLE_FILE_EXT}/i
    flash[:error] = "Must be an text editable file type (#{Site::VALID_EDITABLE_EXTENSIONS.join(', ')})."
    redirect redirect_uri
  end

  site_file = current_site.site_files_dataset.where(path: name).first

  if site_file
    flash[:error] = 'File already exists, cannot create.'
    redirect redirect_uri
  end

  if extname.match(/^\.html|^\.htm/i)
    current_site.install_new_html_file name
  else
    file_path = current_site.files_path(name)
    FileUtils.touch file_path
    File.chmod 0640, file_path

    site_file ||= SiteFile.new site_id: current_site.id, path: name

    site_file.size = 0
    site_file.set size: 0
    site_file.set sha1_hash: Digest::SHA1.hexdigest('')
    site_file.set updated_at: Time.now
    site_file.save
  end

  escaped_name = Rack::Utils.escape_html name

  flash[:success] = %{#{escaped_name} was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/#{escaped_name}">Click here to edit it</a>.}

  redirect redirect_uri
end

def file_upload_response(error=nil)
  flash[:error] = error if error

  if params[:from_button]
    query_string = params[:dir] ? "?"+Rack::Utils.build_query(dir: params[:dir]) : ''
    redirect "/dashboard#{query_string}"
  else
    halt 406, error if error
    halt 200, 'File(s) successfully uploaded.'
  end
end

def require_login_file_upload_ajax
  file_upload_response 'You are not signed in!' unless signed_in?
  file_upload_response 'Please contact support.' if banned?
end

post '/site_files/upload' do
  if params[:filename]
    require_login_file_upload_ajax
    tempfile = Tempfile.new 'neocities_saving_file'

    input = request.body.read
    tempfile.set_encoding input.encoding
    tempfile.write input
    tempfile.close

    params[:files] = [{filename: params[:filename], tempfile: tempfile}]
  else
    require_login
  end

  @errors = []

  if params[:files].nil?
    file_upload_response "Uploaded files were not seen by the server, cancelled. We don't know what's causing this yet. Please contact us so we can help fix it. Thanks!"
  end

  # For migration from original design.. some pages out there won't have the site_id param yet for a while.
  site = params[:site_id].nil? ? current_site : Site[params[:site_id]]

  unless site.owned_by?(current_site)
    file_upload_response 'You do not have permission to save this file. Did you sign in as a different user?'
  end

  params[:files].each_with_index do |file,i|
    dir_name = ''
    dir_name = params[:dir] if params[:dir]

    unless params[:file_paths].nil? || params[:file_paths].empty? || params[:file_paths].length == 0

      file_path = params[:file_paths].select {|file_path|
        file[:filename] == Pathname(file_path).basename.to_s
      }.first

      unless file_path.nil?
        dir_name += '/' + Pathname(file_path).dirname.to_s
      end
    end

    file[:filename] = "#{dir_name}/#{file[:filename]}"
    if current_site.file_size_too_large? file[:tempfile].size
      file_upload_response "#{file[:filename]} is too large, upload cancelled."
    end
    if !site.okay_to_upload? file
      file_upload_response %{#{Rack::Utils.escape_html file[:filename]}: file type (or content in file) is only supported by <a href="/supporter">supporter accounts</a>. <a href="/site_files/allowed_types">Why We Do This</a>}
    end
  end

  uploaded_size = params[:files].collect {|f| f[:tempfile].size}.inject{|sum,x| sum + x }

  if site.file_size_too_large? uploaded_size
    file_upload_response "File(s) do not fit in your available free space, upload cancelled."
  end

  if site.too_many_files? params[:files].length
    file_upload_response "Your site has exceeded the maximum number of files, please delete some files first."
  end

  results = site.store_files params[:files]
  file_upload_response
end

post '/site_files/delete' do
  require_login
  path = HTMLEntities.new.decode params[:filename]
  current_site.delete_file path
  flash[:success] = "Deleted #{params[:filename]}. Please note it can take up to 30 minutes for deleted files to stop being viewable on your site."

  dirname = Pathname(path).dirname
  dir_query = dirname.nil? || dirname.to_s == '.' ? '' : "?dir=#{Rack::Utils.escape dirname}"

  redirect "/dashboard#{dir_query}"
end

post '/site_files/rename' do
  require_login
  path = HTMLEntities.new.decode params[:path]
  new_path = HTMLEntities.new.decode params[:new_path]
  site_file = current_site.site_files.select {|s| s.path == path}.first

  res = site_file.rename new_path

  if res.first == true
    flash[:success] = "Renamed #{path} to #{new_path}"
  else
    flash[:error] = "Failed to rename #{path} to #{new_path}: #{res.last}"
  end

  dirname = Pathname(path).dirname
  dir_query = dirname.nil? || dirname.to_s == '.' ? '' : "?dir=#{Rack::Utils.escape dirname}"

  redirect "/dashboard#{dir_query}"
end

get '/site_files/:username.zip' do |username|
  require_login
  zipfile_path = current_site.files_zip
  content_type 'application/octet-stream'
  attachment   "neocities-#{current_site.username}.zip"
  send_file zipfile_path
end

get %r{\/site_files\/download\/(.+)} do
  require_login
  dont_browser_cache
  not_found if params[:captures].nil? || params[:captures].length != 1
  filename = params[:captures].first
  attachment filename
  send_file current_site.current_files_path(filename)
end

get %r{\/site_files\/text_editor\/(.+)} do
  require_login
  dont_browser_cache

  @filename = params[:captures].first
  extname = File.extname @filename
  @ace_mode = case extname
    when /htm|html/ then 'html'
    when /js/ then 'javascript'
    when /md/ then 'markdown'
    when /css/ then 'css'
    else
      nil
  end

  file_path = current_site.current_files_path @filename

  if File.directory? file_path
    flash[:error] = 'Cannot edit a directory.'
    redirect '/dashboard'
  end

  if !File.exist?(file_path)
    flash[:error] = 'We could not find the requested file.'
    redirect '/dashboard'
  end

  @title = "Editing #{@filename}"

  erb :'site_files/text_editor'
end

get '/site_files/allowed_types' do
  @title = 'Allowed File Types'
  erb :'site_files/allowed_types'
end

get '/site_files/hotlinking' do
  @title = 'Hotlinking Information'
  erb :'site_files/hotlinking'
end

get '/site_files/mount_info' do
  @title = 'Site Mount Information'
  erb :'site_files/mount_info'
end
