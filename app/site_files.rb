get '/site_files/new_page' do
  require_login
  erb :'site_files/new_page'
end

# Redirect from original path
get '/site_files/new' do
  require_login
  redirect '/site_files/new_page'
end

post '/site_files/create_page' do
  require_login
  @errors = []

  params[:pagefilename].gsub!(/[^a-zA-Z0-9_\-.]/, '')
  params[:pagefilename].gsub!(/\.html$/i, '')

  if params[:pagefilename].nil? || params[:pagefilename].strip.empty?
    @errors << 'You must provide a file name.'
    halt erb(:'site_files/new_page')
  end

  name = "#{params[:pagefilename]}.html"

  name = "#{params[:dir]}/#{name}" if params[:dir]

  if current_site.file_exists?(name)
    @errors << %{Web page "#{name}" already exists! Choose another name.}
    halt erb(:'site_files/new_page')
  end

  current_site.install_new_html_file name

  flash[:success] = %{#{name} was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/#{name}">Click here to edit it</a>.}

  redirect params[:dir] ? "/dashboard?dir=#{Rack::Utils.escape params[:dir]}" : '/dashboard'
end

def file_upload_response(error=nil)
  http_error_code = 406
  flash[:error] = error if error

  if params[:from_button]
    query_string = params[:dir] ? "?"+Rack::Utils.build_query(dir: params[:dir]) : ''
    redirect "/dashboard#{query_string}"
  else
    halt http_error_code, error if error
    halt 200, 'File(s) successfully uploaded.'
  end
end

post '/site_files/upload' do
  require_login
  @errors = []
  http_error_code = 406

  if params[:files].nil?
    file_upload_response "Uploaded files were not seen by the server, cancelled. We don't know what's causing this yet. Please contact us so we can help fix it. Thanks!"
  end

  params[:files].each do |file|
    file[:filename] = "#{params[:dir]}/#{file[:filename]}" if params[:dir]
    if current_site.file_size_too_large? file[:tempfile].size
      file_upload_response "#{file[:filename]} is too large, upload cancelled."
    end
    if !current_site.okay_to_upload? file
      file_upload_response %{#{file[:filename]}: file type (or content in file) is only supported by <a href="/plan">supporter accounts</a>. <a href="/site_files/allowed_types">Why We Do This</a>}
    end
  end

  uploaded_size = params[:files].collect {|f| f[:tempfile].size}.inject{|sum,x| sum + x }

  if current_site.file_size_too_large? uploaded_size
    file_upload_response "File(s) do not fit in your available space, upload cancelled."
  end

  results = []
  params[:files].each do |file|
    results << current_site.store_file(file[:filename], file[:tempfile])
  end
  current_site.increment_changed_count if results.include?(true)

  file_upload_response
end

post '/site_files/delete' do
  require_login
  current_site.delete_file params[:filename]

  flash[:success] = "Deleted #{params[:filename]}."
  redirect '/dashboard'
end

get '/site_files/:username.zip' do |username|
  require_login
  zipfile_path = current_site.files_zip
  content_type 'application/octet-stream'
  attachment   "neocities-#{current_site.username}.zip"
  send_file zipfile_path
end

get '/site_files/download/:filename' do |filename|
  require_login
  content_type 'application/octet-stream'
  attachment filename
  current_site.get_file filename
end

get %r{\/site_files\/text_editor\/(.+)} do
  require_login
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

  begin
    @file_data = current_site.get_file @filename
  rescue Errno::ENOENT
    flash[:error] = 'We could not find the requested file.'
    redirect '/dashboard'
  rescue Errno::EISDIR
    flash[:error] = 'Cannot edit a directory.'
    redirect '/dashboard'
  end
  erb :'site_files/text_editor'
end

post %r{\/site_files\/save\/(.+)} do
  require_login_ajax
  filename = params[:captures].first

  tempfile = Tempfile.new 'neocities_saving_file'

  input = request.body.read
  tempfile.set_encoding input.encoding
  tempfile.write input
  tempfile.close

  if current_site.file_size_too_large? tempfile.size
    halt 'File is too large to fit in your space, it has NOT been saved. You will need to reduce the size or upgrade to a new plan.'
  end

  current_site.store_file filename, tempfile

  'ok'
end

get '/site_files/allowed_types' do
  erb :'site_files/allowed_types'
end

get '/site_files/mount_info' do
  erb :'site_files/mount_info'
end
