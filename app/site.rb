get '/site/:username.rss' do |username|
  site = Site[username: username]
  halt 404 if site.nil?
  content_type :xml
  site.to_rss
end

get '/site/:username/?' do |username|
  site = Site[username: username]
  # TODO: There should probably be a "this site was deleted" page.
  not_found if site.nil? || site.is_banned || site.is_deleted

  redirect '/' if site.is_education

  redirect site.uri unless site.profile_enabled

  @title = site.title

  @page = params[:page]
  @page = @page.to_i
  @page = 1 if @page == 0

  if params[:event_id]
    not_found if params[:event_id].is_a?(Array)
    not_found unless params[:event_id].to_i > 0
    event = Event.select(:id).where(id: params[:event_id]).first
    not_found if event.nil?
    events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
  else
    events_dataset = site.latest_events(@page, 10)
  end

  @page_count = events_dataset.page_count || 1
  @pagination_dataset = events_dataset
  @latest_events = events_dataset.all

  meta_robots 'noindex, follow'

  erb :'site', locals: {site: site, is_current_site: site == current_site}
end

MAX_STAT_POINTS = 30
get '/site/:username/stats' do
  @default_stat_points = 7
  @site = Site[username: params[:username]]
  not_found if @site.nil? || @site.is_banned || @site.is_deleted

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
      if params[:days] && params[:days].to_i != 0
        stats_dataset = stats_dataset.limit params[:days]
      else
        params[:days] = @default_stat_points
        stats_dataset = stats_dataset.limit @default_stat_points
      end
    end
  else
    stats_dataset = stats_dataset.limit @default_stat_points
  end

  stats = stats_dataset.all.reverse

  if current_site && @site.owned_by?(current_site) && params[:format] == 'csv'
    content_type 'application/csv'
    attachment "#{current_site.username}-stats.csv"

    return CSV.generate do |csv|
      csv << ['day', 'hits', 'views', 'bandwidth']
      stats.each do |s|
        csv << [s[:created_at].to_s, s[:hits], s[:views], s[:bandwidth]]
      end
    end
  end

  if stats.length > MAX_STAT_POINTS
    puts stats.length
    stats = stats.select.with_index {|a, i| (i % (stats.length / MAX_STAT_POINTS.to_f).round) == 0}
    puts stats.length
  end

  @stats[:stat_days] = stats
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
  @title = "Sites #{username} follows"
  @site = Site[username: username]
  not_found if @site.nil? || @site.is_banned || @site.is_deleted
  @sites = @site.followings.collect {|f| f.site}
  erb :'site/follows'
end

get '/site/:username/followers' do |username|
  @title = "Sites that follow #{username}"
  @site = Site[username: username]
  not_found if @site.nil? || @site.is_banned || @site.is_deleted
  @sites = @site.follows.collect {|f| f.actioning_site}
  erb :'site/followers'
end

post '/site/:username/comment' do |username|
  require_login

  site = Site[username: username]

  last_comment = site.profile_comments_dataset.order(:created_at.desc).first

  if last_comment && last_comment.message == params[:message] && last_comment.created_at > 2.hours.ago
    redirect request.referer
  end

  if site.profile_comments_enabled == false ||
     params[:message].empty? ||
     params[:message].length > Site::MAX_COMMENT_SIZE ||
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
  @title = 'Confirm email'

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
  @title = 'Confirm your Email Address'
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

get '/site/:username/unblock' do |username|
  require_login
  site = Site[username: username]

  if site.nil? || current_site.id == site.id
    redirect request.referer
  end

  current_site.unblock! site
  redirect request.referer
end

get '/site/:username/confirm_phone' do
  require_login
  redirect '/' unless current_site.phone_verification_needed?
  @title = 'Verify your Phone Number'
  erb :'site/confirm_phone'
end

def restart_phone_verification
  current_site.phone_verification_sent_at = nil
  current_site.phone_verification_sid = nil
  current_site.save_changes validate: false
  redirect "/site/#{current_site.username}/confirm_phone"
end

post '/site/:username/confirm_phone' do
  require_login
  redirect '/' unless current_site.phone_verification_needed?

  if params[:phone_intl]
    phone = Phonelib.parse params[:phone_intl]

    if !phone.valid?
      flash[:error] = "Invalid phone number, please try again."
      redirect "/site/#{current_site.username}/confirm_phone"
    end

    if phone.types.include?(:premium_rate) || phone.types.include?(:shared_cost)
      flash[:error] = 'Neocities does not support this type of number, please use another number.'
      redirect "/site/#{current_site.username}/confirm_phone"
    end

    current_site.phone_verification_sent_at = Time.now
    current_site.phone_verification_attempts += 1

    if current_site.phone_verification_attempts > Site::PHONE_VERIFICATION_LOCKOUT_ATTEMPTS
      flash[:error] = 'You have exceeded the number of phone verification attempts allowed.'
      redirect "/site/#{current_site.username}/confirm_phone"
    end

    current_site.save_changes validate: false

    verification = $twilio.verify
                          .v2
                          .services($config['twilio_service_sid'])
                          .verifications
                          .create(to: phone.e164, channel: 'sms')

    current_site.phone_verification_sid = verification.sid
    current_site.save_changes validate: false

    flash[:success] = 'Validation message sent! Check your phone and enter the code below.'
  else

    restart_phone_verification if current_site.phone_verification_sent_at < Time.now - Site::PHONE_VERIFICATION_EXPIRATION_TIME
    minutes_remaining = ((current_site.phone_verification_sent_at - (Time.now - Site::PHONE_VERIFICATION_EXPIRATION_TIME))/60).round

    begin
      # Check code
      vc = $twilio.verify
                  .v2
                  .services($config['twilio_service_sid'])
                  .verification_checks
                  .create(verification_sid: current_site.phone_verification_sid, code: params[:code])

      # puts vc.status (pending if failed, approved if it passed)
      if vc.status == 'approved'
        current_site.phone_verified = true
        current_site.save_changes validate: false
      else
        flash[:error] = "Code was not correct, please try again. If the phone number you entered was incorrect, you can re-enter the number after #{minutes_remaining} more minutes have passed."
      end

    rescue Twilio::REST::RestError => e
      if e.message =~ /60202/
        flash[:error] = "You have exhausted your check attempts. Please try again in #{minutes_remaining} minutes."
      elsif e.message =~ /20404/ # Unable to create record
        restart_phone_verification
      else
        raise e
      end
    end
  end

  # Will redirect to / automagically if phone was verified
  redirect "/site/#{current_site.username}/confirm_phone"
end
