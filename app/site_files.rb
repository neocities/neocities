post '/site_files/delete' do
  require_login
  path = HTMLEntities.new.decode params[:filename]
  begin
    current_site.delete_file path
  rescue Sequel::NoExistingObject
    # the deed was presumably already done
  end
  flash[:success] = "Deleted #{Rack::Utils.escape_html params[:filename]}."

  dirname = Pathname(path).dirname
  dir_query = dirname.nil? || dirname.to_s == '.' ? '' : "?dir=#{Rack::Utils.escape dirname}"

  redirect "/dashboard#{dir_query}"
end

post '/site_files/rename' do
  require_login
  path = HTMLEntities.new.decode params[:path]
  new_path = HTMLEntities.new.decode params[:new_path]
  site_file = current_site.site_files.select {|s| s.path == path}.first

  escaped_path = Rack::Utils.escape_html path
  escaped_new_path = Rack::Utils.escape_html new_path

  if site_file.nil?
    flash[:error] = "File #{escaped_path} does not exist."
  else
    res = site_file.rename new_path

    if res.first == true
      flash[:success] = "Renamed #{escaped_path} to #{escaped_new_path}"
    else
      flash[:error] = "Failed to rename #{escaped_path} to #{escaped_new_path}: #{Rack::Utils.escape_html res.last}"
    end
  end

  dirname = Pathname(path).dirname
  dir_query = dirname.nil? || dirname.to_s == '.' ? '' : "?dir=#{Rack::Utils.escape dirname}"

  redirect "/dashboard#{dir_query}"
end

get '/site_files/download' do
  require_login

  if !current_site.dl_queued_at.nil? && current_site.dl_queued_at > 1.hour.ago
    flash[:error] = 'Site downloads are currently limited to once per hour, please try again later.'
    redirect request.referer
  end

  content_type 'application/zip'
  attachment   "neocities-#{current_site.username}.zip"

  current_site.dl_queued_at = Time.now
  current_site.save_changes validate: false

  directory_path = current_site.files_path

  stream do |out|
    ZipTricks::Streamer.open(out) do |zip|
      Dir["#{directory_path}/**/*"].each do |file|
        next if File.directory?(file)

        zip_path = file.sub("#{directory_path}/", '')
        zip.write_stored_file(zip_path) do |file_writer|
          File.open(file, 'rb') do |file|
            IO.copy_stream(file, file_writer)
          end
        end
      end
    end
  end
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
  redirect '/site_files/text_editor?filename=' + Rack::Utils.escape(@filename)
end

get '/site_files/text_editor' do
  require_login
  dont_browser_cache

  @filename = params[:filename]

  if @filename.nil? || @filename.strip.empty?
    flash[:error] = 'No filename specified.'
    redirect '/dashboard'
  end

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

post '/site_files/chat' do
  require_login
  dont_browser_cache
  headers 'X-Accel-Buffering' => 'no'
  halt(403) unless parent_site.supporter?

  # Ensure the request is treated as a stream
  stream do |out|
    url = 'https://api.anthropic.com/v1/messages'

    headers = {
        "anthropic-version" => "2023-06-01",
        "anthropic-beta" => "messages-2023-12-15",
        "content-type" => "application/json",
        "x-api-key" => $config['anthropic_api_key']
    }

    body = {
      model: "claude-3-haiku-20240307",
      system: params[:system],
      messages: JSON.parse(params[:messages]),
      max_tokens: 4096,
      temperature: 0.5,
      stream: true
    }.to_json

    res = HTTP.headers(headers).post(url, body: body)

    while(buffer = res.body.readpartial)
      out << buffer
    end
  end
end