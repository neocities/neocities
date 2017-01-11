get '/site/:username.rss' do |username|
  site = Site[username: username]
  content_type :xml
  site.to_rss.to_xml
end

get '/site/:username/?' do |username|
  site = Site[username: username]
  # TODO: There should probably be a "this site was deleted" page.
  not_found if site.nil? || site.is_banned || site.is_deleted

  redirect '/' if site.is_education

  @title = site.title

  @page = params[:page]
  @page = @page.to_i
  @page = 1 if @page == 0

  if params[:event_id]
    not_found unless params[:event_id].is_integer?
    event = Event.select(:id).where(id: params[:event_id]).first
    not_found if event.nil?
    events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
  else
    events_dataset = site.latest_events(@page, 10)
  end

  @page_count = events_dataset.page_count || 1
  @pagination_dataset = events_dataset
  @latest_events = events_dataset.all

  erb :'site', locals: {site: site, is_current_site: site == current_site}
end

get '/site/:username/archives' do
  require_login
  @site = Site[username: params[:username]]
  not_found if @site.nil?
  redirect request.referrer unless current_site.id == @site.id

  @archives = @site.archives_dataset.limit(300).order(:updated_at.desc).all

  erb :'site/archives'
end

get '/site/:username/stats' do
  @site = Site[username: params[:username]]
  not_found if @site.nil?

  @title = "Site stats for #{@site.host}"

  @stats = {}

  %i{referrers locations paths}.each do |stat|
    @stats[stat] = @site.send("stat_#{stat}_dataset".to_sym).order(:views.desc).limit(100).all
  end

  @stats[:locations].collect! do |location|
    location_name = ''

    location_name += location.city_name if location.city_name

    if location.region_name
      # Some of the region names are numbers for some reason.
      begin
        Integer(location.region_name)
      rescue
        location_name += ', ' unless location_name == ''
        location_name += location.region_name
      end
    end

    if location.country_code2 && !$country_codes[location.country_code2].nil?
      location_name += ', ' unless location_name == ''
      location_name += $country_codes[location.country_code2]
    end

    location_hash = {name: location_name, views: location.views}
    if location.latitude && location.longitude
      location_hash.merge! latitude: location.latitude, longitude: location.longitude
    end
    location_hash
  end

  stats_dataset = @site.stats_dataset.order(:created_at.desc).exclude(created_at: Date.today)

  if @site.supporter?
    unless params[:days].to_s == 'sincethebigbang'
      if params[:days]
        stats_dataset.limit! params[:days]
      else
        stats_dataset.limit! 7
      end
    end
  else
    stats_dataset.limit! 7
  end

  @stats[:stat_days] = stats_dataset.all.reverse
  @multi_tooltip_template = "<%= datasetLabel %> - <%= value %>"

  erb :'site/stats', locals: {site: @site}
end

post '/site/:username/set_editor_theme' do
  require_login
  current_site.editor_theme = params[:editor_theme]
  current_site.save_changes validate: false
  'ok'
end

get '/site/:username/follows' do |username|
  @site = Site[username: username]
  not_found if @site.nil?
  @sites = @site.followings.collect {|f| f.site}
  erb :'site/follows'
end

get '/site/:username/followers' do |username|
  @site = Site[username: username]
  not_found if @site.nil?
  @sites = @site.follows.collect {|f| f.actioning_site}
  erb :'site/followers'
end

post '/site/:username/comment' do |username|
  require_login

  site = Site[username: username]

  if site.profile_comments_enabled == false ||
     params[:message].empty? ||
     site.is_blocking?(current_site) ||
     current_site.is_blocking?(site) ||
     current_site.commenting_allowed? == false ||
     (current_site.is_a_jerk? && site.id != current_site.id && !site.is_following?(current_site))
    redirect request.referrer
  end

  site.add_profile_comment(
    actioning_site_id: current_site.id,
    message: params[:message]
  )

  redirect request.referrer
end

get '/site/:username/tip' do |username|
  @site = Site[username: username]
  redirect request.referrer unless @site.tipping_enabled?
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
    flash[:error] = result
  end

  redirect "/dashboard?dir=#{Rack::Utils.escape params[:dir]}"
end

get '/site/:username/confirm_email/:token' do
  if current_site && current_site.email_confirmed
    return erb(:'site_email_confirmed')
  end

  site = Site[username: params[:username]]

  if site.nil?
    return erb(:'site_email_not_confirmed')
  end

  if site.email_confirmed
    return erb(:'site_email_confirmed')
  end

  if site.email_confirmation_token == params[:token]
    site.email_confirmation_token = nil
    site.email_confirmation_count = 0
    site.email_confirmed = true
    site.save_changes

    erb :'site_email_confirmed'
  else
    erb :'site_email_not_confirmed'
  end
end

get '/site/:username/confirm_email' do
  require_login
  @fromsettings = session[:fromsettings]
  redirect '/' if current_site.username != params[:username] || !current_site.parent? || current_site.email_confirmed
  erb :'site/confirm_email'
end

post '/site/:username/confirm_email' do
  require_login

  redirect '/' if current_site.username != params[:username] || !current_site.parent? || current_site.email_confirmed

  # Update email, resend token
  if params[:email]
    send_confirmation_email @site
  end

  if params[:token].blank?
    flash[:error] = 'You must enter a valid token.'
    redirect "/site/#{current_site.username}/confirm_email"
  end

  if current_site.email_confirmation_token == params[:token]
    current_site.email_confirmation_token = nil
    current_site.email_confirmation_count = 0
    current_site.email_confirmed = true
    current_site.save_changes

    if session[:fromsettings]
      session[:fromsettings] = nil
      flash[:success] = 'Email address changed.'
      redirect '/settings#email'
    end

    redirect '/tutorial'
  else
    flash[:error] = 'You must enter a valid token.'
    redirect "/site/#{current_site.username}/confirm_email"
  end
end

post '/site/:username/report' do |username|
  site = Site[username: username]

  redirect request.referer if site.nil?

  if !recaptcha_valid?
    flash[:error] = 'Captcha was not filled out (or was filled out incorrectly)'
    redirect request.referer
  end

  report = Report.new site_id: site.id, type: params[:type], comments: params[:comments]

  if current_site
    redirect request.referer if current_site.id == site.id
    report.reporting_site_id = current_site.id
  else
    report.ip = request.ip
  end

  report.save

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'report@neocities.org',
    subject: "[Neocities Report] #{site.username} has been reported for #{report.type}",
    body: "Reported by #{report.reporting_site_id ? report.reporting_site.username : report.ip}: #{report.comments}"
  })

  flash[:success] = "Thank you for the report, we will look into it."

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
