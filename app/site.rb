get '/site/:username.rss' do |username|
  site = Site[username: username]
  content_type :xml
  site.to_rss.to_xml
end

get '/site/:username/?' do |username|
  site = Site[username: username]
  not_found if site.nil? || site.is_banned

  @title = site.title

  @current_page = params[:current_page]
  @current_page = @current_page.to_i
  @current_page = 1 if @current_page == 0

  if params[:event_id]
    event = Event.select(:id).where(id: params[:event_id]).first
    not_found if event.nil?
    events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
  else
    events_dataset = site.latest_events(@current_page, 10)
  end

  @page_count = events_dataset.page_count || 1
  @latest_events = events_dataset.all

  erb :'site', locals: {site: site, is_current_site: site == current_site}
end

post '/site/:username/set_editor_theme' do
  require_login
  current_site.editor_theme = params[:editor_theme]
  current_site.save_changes validate: false
  'ok'
end

post '/site/:username/comment' do |username|
  require_login

  site = Site[username: username]

  if(site.profile_comments_enabled == false ||
     params[:message].empty? ||
     site.is_blocking?(current_site) ||
     current_site.is_blocking?(site) ||
     current_site.commenting_allowed? == false)
    redirect "/site/#{username}"
  end

  site.add_profile_comment(
    actioning_site_id: current_site.id,
    message: params[:message]
  )

  redirect "/site/#{username}"
end

get '/site/:username/tip' do |username|
  @site = Site[username: username]
  @title = "Tip #{@site.title}"
  erb :'tip'
end

post '/site/:site_id/toggle_follow' do |site_id|
  require_login
  content_type :json
  site = Site[id: site_id]
  {result: (current_site.toggle_follow(site) ? 'followed' : 'unfollowed')}.to_json
end

post '/site/create_directory' do
  require_login

  path = "#{params[:dir] || ''}/#{params[:name]}"

  result = current_site.create_directory path

  if result != true
    flash[:error] = e.message
  end

  redirect "/dashboard?dir=#{Rack::Utils.escape params[:dir]}"
end

get '/site/:username/confirm_email/:token' do
  site = Site[username: params[:username]]
  if site.email_confirmation_token == params[:token]
    site.email_confirmed = true
    site.save_changes

    erb :'site_email_confirmed'
  else
    erb :'site_email_not_confirmed'
  end
end

post '/site/:username/report' do |username|
  site = Site[username: username]

  redirect request.referer if site.nil?

  report = Report.new site_id: site.id, type: params[:type], comments: params[:comments]

  if current_site
    redirect request.referer if current_site.id == site.id
    report.reporting_site_id = current_site.id
  else
    report.ip = Site.hash_ip request.ip
  end

  report.save

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'report@neocities.org',
    subject: "[Neocities Report] #{site.username} has been reported for #{report.type}",
    body: "Reported by #{report.reporting_site_id ? report.reporting_site.username : report.ip}: #{report.comments}"
  })

  redirect request.referer
end

post '/site/:username/block' do |username|
  require_login
  site = Site[username: username]
  redirect request.referer if current_site.id == site.id

  current_site.block! site

  if request.referer.match /\/site\/#{username}/i
    redirect '/'
  else
    redirect request.referer
  end
end