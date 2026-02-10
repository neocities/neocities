require 'base64'

get '/api' do
  @title = 'Developers API'
  @description = 'Use the Neocities API to upload files and manage your site programmatically.'
  erb :'api'
end

post '/api/upload_hash' do
  require_api_credentials
  res = {}
  files = []

  params.each do |path, sha1_hash|
    unless sha1_hash.is_a?(String)
      api_error 400, 'nested_parameters_not_allowed', 'nested parameters are not allowed; each path must directly map to a SHA-1 hash string'
    end
  end

  params.each do |k,v|
    res[k] = current_site.sha1_hash_match? k, v
  end
  api_success files: res
end

get '/api/list' do
  require_api_credentials

  files = []

  if params[:path].nil? || params[:path].empty? || params[:path] == '/'
    file_list = current_site.site_files
  else
    file_list = current_site.file_list params[:path]
  end

  file_list.each do |file|
    new_file = {}
    new_file[:path] = file[:path]
    new_file[:is_directory] = file[:is_directory]
    new_file[:size] = file[:size] unless file[:is_directory]
    new_file[:created_at] = file[:created_at].rfc2822
    new_file[:updated_at] = file[:updated_at].rfc2822
    new_file[:sha1_hash] = file[:sha1_hash] unless file[:is_directory]
    files << new_file
  end

  files.each {|f| f[:path].sub!(/^\//, '')}

  api_success files: files
end

def extract_files(params, files = [])
  # Check if the entire input is directly an array of files
  if params.is_a?(Array)
    params.each do |item|
      # Call extract_files on each item if it's an Array or Hash to handle nested structures
      if item.is_a?(Array) || item.is_a?(Hash)
        extract_files(item, files)
      end
    end
  elsif params.is_a?(Hash)
    params.each do |key, value|
      # If the value is a Hash and contains a :tempfile key, it's considered an uploaded file.
      if value.is_a?(Hash) && value.has_key?(:tempfile) && !value[:tempfile].nil?
        files << {filename: value[:name], tempfile: value[:tempfile]}
      elsif value.is_a?(Array)
        value.each do |val|
          if val.is_a?(Hash) && val.has_key?(:tempfile) && !val[:tempfile].nil?
            # Directly add the file info if it's an uploaded file within an array
            files << {filename: val[:name], tempfile: val[:tempfile]}
          elsif val.is_a?(Hash) || val.is_a?(Array)
            # Recursively search for more files if the element is a Hash or Array
            extract_files(val, files)
          end
        end
      elsif value.is_a?(Hash)
        # Recursively search for more files if the value is a Hash
        extract_files(value, files)
      end
    end
  end
  files
end

post '/api/upload' do
  require_api_credentials
  files = extract_files params

  if !params[:username].blank?
    site = Site[username: params[:username]]

    if site.nil? || site.is_deleted
      api_error 400, 'site_not_found', "could not find site"
    end

    if site.owned_by?(current_site)
      @_site = site
    else
      api_error 400, 'site_not_allowed', "not allowed to change this site with your current logged in site"
    end
  end

  results = current_site.store_files files

  if results.is_a?(Hash) && results[:error]
    api_error 400, results[:error_type], results[:message]
  end

  if results.is_a?(Array)
    success_count = results.count(true)
    unchanged_count = results.count(:unchanged)
    failure_count = results.count(false)
    total = results.length
    change_attempts = total - unchanged_count

    if failure_count == total
      api_error 500, 'upload_failed', 'all files failed to upload'
    elsif failure_count > 0
      message_parts = []
      if success_count > 0
        denominator = change_attempts.zero? ? total : change_attempts
        message_parts << "#{success_count} of #{denominator} file(s) uploaded"
      end
      message_parts << "#{unchanged_count} file(s) already up to date" if unchanged_count > 0
      message_parts << "#{failure_count} file(s) failed" if failure_count > 0
      api_success message_parts.join(', ')
    elsif success_count > 0
      if unchanged_count > 0
        api_success "#{success_count} file(s) uploaded, #{unchanged_count} already up to date"
      else
        api_success 'your file(s) have been successfully uploaded'
      end
    else
      api_success 'no changes, files already up to date'
    end
  else
    api_success 'your file(s) have been successfully uploaded'
  end
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
  return true if current_site && csrf_safe?

  if !request.env['HTTP_AUTHORIZATION'].nil?
    init_api_credentials
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

  if site.nil? || site.is_banned || site.is_deleted || !(site.required_validations_met?)
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
