require 'base64'

get '/api' do
  @title = 'Developers API'
  erb :'api'
end

post '/api/upload_hash' do
  require_api_credentials
  res = {}
  files = []
  params.each do |k,v|
    res[k] = current_site.sha1_hash_match? k, v
  end
  api_success files: res
end

get '/api/list' do
  require_api_credentials

  files = []

  if params[:path].nil? || params[:path].empty?
    file_list = current_site.site_files
  else
    file_list = current_site.file_list params[:path]
  end

  file_list.each do |file|
    new_file = {}
    new_file[:path] = file[:path]
    new_file[:is_directory] = file[:is_directory]
    new_file[:size] = file[:size] unless file[:is_directory]
    new_file[:updated_at] = file[:updated_at].rfc2822
    new_file[:sha1_hash] = file[:sha1_hash] unless file[:is_directory]
    files << new_file
  end

  files.each {|f| f[:path].sub!(/^\//, '')}

  api_success files: files
end

post '/api/upload' do
  require_api_credentials

  files = []
  params.each do |k,v|
    next unless v.is_a?(Hash) && v[:tempfile]
    path = k.to_s
    files << {filename: k || v[:filename], tempfile: v[:tempfile]}
  end

  api_error 400, 'missing_files', 'you must provide files to upload' if files.empty?

  uploaded_size = files.collect {|f| f[:tempfile].size}.inject{|sum,x| sum + x }

  if current_site.file_size_too_large? uploaded_size
    api_error 400, 'too_large', 'files are too large to fit in your space, try uploading smaller (or less) files'
  end

  if current_site.too_many_files?(files.length)
    api_error 400, 'too_many_files', "cannot exceed the maximum site files limit (#{current_site.plan_feature(:maximum_site_files)}), #{current_site.supporter? ? 'please contact support' : 'please upgrade to a supporter account'}"
  end

  files.each do |file|
    if !current_site.okay_to_upload?(file)
      api_error 400, 'invalid_file_type', "#{file[:filename]} is not a valid file type (or contains not allowed content) for this site, files have not been uploaded"
    end

    if File.directory? file[:filename]
      api_error 400, 'directory_exists', 'this name is being used by a directory, cannot continue'
    end
  end

  results = current_site.store_files files
  api_success 'your file(s) have been successfully uploaded'
end

post '/api/rename' do
  require_api_credentials

  api_error 400, 'missing_arguments', 'you must provide path and new_path' if params[:path].blank? || params[:new_path].blank?

  path = current_site.scrubbed_path params[:path]
  new_path = current_site.scrubbed_path params[:new_path]

  unless path.is_a?(String)
    api_error 400, 'bad_path', "#{path} is not a valid path, cancelled renaming"
  end

  unless new_path.is_a?(String)
    api_error 400, 'bad_new_path', "#{new_path} is not a valid new_path, cancelled renaming"
  end

  site_file = current_site.site_files.select {|sf| sf.path == path}.first

  if site_file.nil?
    api_error 400, 'missing_file', "could not find #{path}"
  end

  res = site_file.rename new_path

  if res.first == true
    api_success "#{path} has been renamed to #{new_path}"
  else
    api_error 400, 'rename_error', res.last
  end
end

post '/api/delete' do
  require_api_credentials

  api_error 400, 'missing_filenames', 'you must provide files to delete' if params[:filenames].nil? || params[:filenames].empty?

  paths = []
  params[:filenames].each do |path|
    unless path.is_a?(String)
      api_error 400, 'bad_filename', "#{path} is not a valid filename, canceled deleting"
    end

    if current_site.files_path(path) == current_site.files_path
      api_error 400, 'cannot_delete_site_directory', 'cannot delete the root directory of the site'
    end

    if !current_site.file_exists?(path)
      api_error 400, 'missing_files', "#{path} was not found on your site, canceled deleting"
    end

    if path == 'index.html' || path == '/index.html'
      api_error 400, 'cannot_delete_index', 'you cannot delete your index.html file, canceled deleting'
    end

    paths << path
  end

  paths.each do |path|
    current_site.delete_file(path)
  end

  api_success 'file(s) have been deleted'
end

get '/api/info' do
  if params[:sitename]
    site = Site[username: params[:sitename]]
    api_error 400, 'site_not_found', "could not find site #{params[:sitename]}" if site.nil? || site.is_banned
    api_success api_info_for(site)
  else
    init_api_credentials
    api_success api_info_for(current_site)
  end
end

get '/api/key' do
  require_api_credentials
  current_site.generate_api_key! if current_site.api_key.blank?
  api_success api_key: current_site.api_key
end

def api_info_for(site)
  {
    info: {
      sitename: site.username,
      views: site.views,
      hits: site.hits,
      created_at: site.created_at.rfc2822,
      last_updated: site.site_updated_at ? site.site_updated_at.rfc2822 : nil,
      domain: site.domain,
      tags: site.tags.collect {|t| t.name}
    }
  }
end

# Catch-all for missing api calls

get '/api/:name' do
  api_not_found
end

post '/api/:name' do
  api_not_found
end

def require_api_credentials
  return true if current_site

  if !request.env['HTTP_AUTHORIZATION'].nil?
    init_api_credentials
    api_error(403, 'email_not_validated', 'you need to validate your email address before using the API') if email_not_validated?
  else
    api_error_invalid_auth
  end
end

def init_api_credentials
  auth = request.env['HTTP_AUTHORIZATION']

  begin
    if bearer_match = auth.match(/^Bearer (.+)/)
      api_key = bearer_match.captures.first
      api_error_invalid_auth if api_key.nil? || api_key.empty?
    else
      user, pass = Base64.decode64(auth.match(/Basic (.+)/)[1]).split(':')
    end
  rescue
    api_error_invalid_auth
  end

  if defined?(api_key) && !api_key.blank?
    site = Site[api_key: api_key]
  elsif defined?(user) && defined?(pass)
    site = Site.get_site_from_login user, pass
  else
    api_error_invalid_auth
  end

  if site.nil? || site.is_banned || site.is_deleted
    api_error_invalid_auth
  end

  DB['update sites set api_calls=api_calls+1 where id=?', site.id].first

  session[:id] = site.id
end

def api_success(message_or_obj)
  output = {result: 'success'}

  if message_or_obj.is_a?(String)
    output[:message] = message_or_obj
  else
    output.merge! message_or_obj
  end

  api_response(200, output)
end

def api_response(status, output)
  halt status, JSON.pretty_generate(output)+"\n"
end

def api_error(status, error_type, message)
  api_response(status, result: 'error', error_type: error_type, message: message)
end

def api_error_invalid_auth
  api_error 403, 'invalid_auth', 'invalid credentials - please check your username and password (or your api key)'
end

def api_not_found
  api_error 404, 'not_found', 'the requested api call does not exist'
end
