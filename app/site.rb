get '/site/:username.rss' do |username|
  site = Site[username: username]
  halt 404 if site.nil? || (current_site && site.is_blocking?(current_site))
  content_type :xml
  site.to_rss
end

get '/site/:username/?' do |username|
  site = Site[username: username]
  # TODO: There should probably be a "this site was deleted" page.
  not_found if site.nil? || site.is_banned || site.is_deleted || (current_site && site.is_blocking?(current_site))

  redirect '/' if site.is_education

  redirect site.uri unless site.profile_enabled

  @title = site.title
  @description = "#{site.username}'s Neocities site profile, updates, and comments."

  @page = params[:page]
  @page = 1 if @page.not_an_integer?

  if params[:event_id]
    not_found if params[:event_id].not_an_integer?
    not_found if params[:event_id].to_i > 2_147_483_647 # max integer
    event = Event.where(id: params[:event_id]).exclude(is_deleted: true).first
    not_found if event.nil?
    event_site = event.site
    event_actioning_site = event.actioning_site
    not_found if current_site && event_site && event_site.is_blocking?(current_site)
    not_found if current_site && event_actioning_site && event_actioning_site.is_blocking?(current_site)
    events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
  else
    events_dataset = site.latest_events(@page, current_site)
  end

  @page_count = events_dataset.page_count || 1
  @pagination_dataset = events_dataset
  @latest_events = events_dataset.all

  meta_robots 'noindex, follow'

  erb :'site', locals: {site: site, is_current_site: site == current_site}
end

MAX_STAT_POINTS = 30
get '/site/:username/stats' do
  require_login

  @default_stat_points = 7
  @site = Site[username: params[:username]]
  not_found if @site.nil? || @site.is_banned || @site.is_deleted

  @can_view_site_stats = current_site.is_admin || @site.owned_by?(current_site)
  not_found unless @can_view_site_stats

  @title = "Traffic stats for #{@site.host}"
  @description = "See daily visits and file requests for #{@site.username}'s Neocities site."
  @stats = {}

  stats_dataset = @site.stats_dataset.order(:created_at.desc).exclude(created_at: Date.today)
  @selected_stat_range = @default_stat_points

  if @site.supporter?
    if params[:days].to_s == 'sincethebigbang'
      @selected_stat_range = 'sincethebigbang'
    else
      unless params[:days].not_an_integer?
        days_param = params[:days].to_i
        if days_param.positive? && days_param < 9000
          stats_dataset = stats_dataset.limit days_param
          @selected_stat_range = days_param
        elsif days_param >= 9000
          params[:days] = 'sincethebigbang'
          @selected_stat_range = 'sincethebigbang'
        else
          params[:days] = @default_stat_points
          stats_dataset = stats_dataset.limit @default_stat_points
        end
      else
        params[:days] = @default_stat_points
        stats_dataset = stats_dataset.limit @default_stat_points
      end
    end
  else
    stats_dataset = stats_dataset.limit @default_stat_points
  end

  stats = stats_dataset.all.reverse

  if @can_view_site_stats && params[:format] == 'csv'
    content_type 'application/csv'
    attachment "#{@site.username}-stats.csv"

    return CSV.generate do |csv|
      csv << ['day', 'hits', 'views', 'bandwidth']
      stats.each do |s|
        csv << [s[:created_at].to_s, s[:hits], s[:views], s[:bandwidth]]
      end
    end
  end

  total_views = stats.sum {|stat| stat.views || 0}
  total_hits = stats.sum {|stat| stat.hits || 0}
  @stat_summary = {
    views: total_views,
    hits: total_hits,
    average_views: stats.empty? ? 0 : (total_views.to_f / stats.length).round,
    days: stats.length
  }
  @stat_range_label = if @selected_stat_range == 'sincethebigbang'
    'All available history'
  else
    "Last #{@selected_stat_range} days"
  end
  @stat_range_options = {
    7 => '7 days',
    30 => '30 days',
    90 => '90 days',
    365 => '1 year',
    'sincethebigbang' => 'All time'
  }
  @follow_count = @site.follows_dataset.count

  if stats.length > MAX_STAT_POINTS
    stats = stats.select.with_index {|a, i| (i % (stats.length / MAX_STAT_POINTS.to_f).round) == 0}
  end

  @stats[:stat_days] = stats

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
  @description = "See which Neocities sites #{username} follows."
  @site = Site[username: username]
  not_found if @site.nil? || @site.is_deleted || (current_site && (@site.is_blocking?(current_site) || current_site.is_blocking?(@site)))

  params[:page] ||= "1"

  @pagination_dataset = @site.followings_dataset.paginate(params[:page].to_i, Site::FOLLOW_PAGINATION_LIMIT)
  erb :'site/follows'
end

get '/site/:username/followers' do |username|
  @title = "Sites that follow #{username}"
  @description = "See which Neocities sites follow #{username}."
  @site = Site[username: username]
  not_found if @site.nil? || @site.is_deleted || (current_site && (@site.is_blocking?(current_site) || current_site.is_blocking?(@site)))

  params[:page] ||= "1"

  @pagination_dataset = @site.follows_dataset.paginate(params[:page].to_i, Site::FOLLOW_PAGINATION_LIMIT)
  erb :'site/followers'
end

post '/site/:username/comment' do |username|
  require_login

  site = Site[username: username]
  message = normalize_comment_message(params[:message])
  message_error = comment_message_error(message)

  if current_site && (site.is_blocking?(current_site) || current_site.is_blocking?(site))
    flash[:error] = comment_unavailable_message(site)
    redirect request.referer
  end

  last_comment = site.profile_comments_dataset.order(:created_at.desc).first

  if last_comment && last_comment.message == message && last_comment.created_at > 2.hours.ago
    flash[:error] = 'You already posted that comment.'
    redirect request.referer
  end

  if site.profile_comments_enabled == false ||
     message_error ||
     site.is_blocking?(current_site) ||
     current_site.is_blocking?(site) ||
     current_site.commenting_allowed? == false ||
     (current_site.is_a_jerk? && site.id != current_site.id && !site.is_following?(current_site))
    flash[:error] = message_error || comment_unavailable_message(site)
    redirect request.referrer
  end

  site.add_profile_comment(
    actioning_site_id: current_site.id,
    message: message
  )

  redirect request.referrer
end

post '/site/:site_id/toggle_follow' do |site_id|
  require_login
  content_type :json
  site = Site[id: site_id]
  return 404 if site.nil?
  return 403 if site.is_blocking?(current_site)
  {result: (current_site.toggle_follow(site) ? 'followed' : 'unfollowed')}.to_json
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
    site.email_reviewed_at = Time.now
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

post '/site/:username/confirm_email/resend' do
  require_login

  redirect '/' if current_site.username != params[:username] || !current_site.parent? || current_site.email_confirmed

  request.env['HTTP_REFERER'] ||= "/site/#{current_site.username}/confirm_email"

  send_confirmation_email current_site
  flash[:success] = 'Confirmation email re-sent.'
  redirect "/site/#{current_site.username}/confirm_email"
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
    current_site.email_reviewed_at = Time.now
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

  if request.referer.match /\/site\/#{Regexp.quote(username)}/i
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
