get '/admin' do
  require_admin
  @banned_sites = Site.select(:username).filter(is_banned: true).order(:username).all
  @nsfw_sites = Site.select(:username).filter(is_nsfw: true).order(:username).all
  erb :'admin'
end

get '/admin/reports' do
  require_admin
  @page = params[:page] ? params[:page].to_i : 1
  @page = 1 if @page < 1
  @per_page = 51
  
  @reports = Report.join(:sites, id: :site_id).where(sites__is_deleted: false, sites__is_banned: false).order(:reports__created_at.desc).select_all(:reports).paginate(@page, @per_page)
  @pagination_dataset = @reports
  
  erb :'admin/reports'
end

post '/admin/reports/:report_id/dismiss' do
  require_admin
  content_type :json
  
  report = Report[params[:report_id]]
  return {success: false, error: 'Report not found'}.to_json if report.nil?
  
  report.destroy
  {success: true, message: 'Report dismissed'}.to_json
end

post '/admin/site_files/train' do
  require_admin
  site = Site[params[:site_id]]
  site_file = site.site_files_dataset.where(path: params[:path]).first
  not_found if site_file.nil?
  site.untrain site_file.path
  site.train site_file.path, params[:classifier]
  'ok'
end

get '/admin/usage' do
  require_admin
  today = Date.today
  current_month = Date.new today.year, today.month, 1

  @monthly_stats = []

  month = current_month

  until month.year == 2016 && month.month == 2 do

    stats = DB["select sum(views) as views, sum(hits) as hits,sum(bandwidth) as bandwidth from daily_site_stats where created_at::text LIKE '#{month.year}-#{month.strftime('%m')}-%'"].first

    stats.keys.each do |key|
      stats[key] ||= 0
    end

    stats.collect {|s| s == 0}.uniq

    if stats[:views] != 0 && stats[:hits] != 0 && stats[:bandwidth] != 0
      popular_sites = DB[
        'select sum(bandwidth) as bandwidth,username from stats left join sites on sites.id=stats.site_id where stats.created_at >= ? and stats.created_at < ? group by username order by bandwidth desc limit 50',
        month,
        month.next_month
      ].all

      @monthly_stats.push stats.merge(date: month).merge(popular_sites: popular_sites)
    end

    month = month.prev_month
  end

  erb :'admin/usage'
end

get '/admin/email' do
  require_admin
  erb :'admin/email'
end

get '/admin/stats' do
  require_admin
  @stats = {
    total_hosted_site_hits: DB['SELECT SUM(hits) FROM sites'].first[:sum],
    total_hosted_site_views: DB['SELECT SUM(views) FROM sites'].first[:sum],
    total_site_changes: DB['select max(changed_count) from sites'].first[:max],
    total_sites: Site.count
  }

  # Start with the date of the first created site
  start = Site.select(:created_at).
               exclude(created_at: nil).
               order(:created_at).
               first[:created_at].to_date

  runner = start
  monthly_stats = []
  now = Date.today

  while Date.new(runner.year, runner.month, 1) <= Date.new(now.year, now.month, 1)
    # Get sites created in this time range
    sites_in_range = Site.where(created_at: runner..runner.next_month)
    sites_from_start = Site.where(created_at: start..runner.next_month)
    
    supporters_count = Site.where(created_at: start..runner.next_month, parent_site_id: nil)
                          .where(
                            Sequel.|(
                              ~{stripe_customer_id: nil} & ~{stripe_subscription_id: nil} & {plan_ended: [false, nil]} & ~{plan_type: ['free', 'special']},
                              {paypal_active: true}
                            )
                          ).count
    
    monthly_stats.push(
      date: runner,
      sites_created: sites_in_range.count,
      total_from_start: sites_from_start.count,
      supporters: supporters_count,
    )

    runner = runner.next_month
  end

  @stats[:monthly_stats] = monthly_stats
  
  @stats[:current_supporters] = Site.where(parent_site_id: nil)
                                    .where(
                                      Sequel.|(
                                        ~{stripe_customer_id: nil} & ~{stripe_subscription_id: nil} & {plan_ended: [false, nil]} & ~{plan_type: ['free', 'special']},
                                        {paypal_active: true}
                                      )
                                    ).count
  @stats[:supporter_percentage] = (@stats[:current_supporters].to_f / @stats[:total_sites] * 100).round(2)

  erb :'admin/stats'
end

get '/admin/ban_history' do
  require_admin

  @title = 'Ban History'
  @page = params[:page] ? params[:page].to_i : 1
  @page = 1 if @page < 1
  @per_page = 51

  @sites = Site.where(is_banned: true).order(:banned_at.desc).exclude(banned_at: nil).  paginate(@page, @per_page)
  @pagination_dataset = @sites

  erb :'admin/ban_history'
end

post '/admin/email' do
  require_admin
  %i{subject body}.each do |k|
    if params[k].nil? || params[k].empty?
      flash[:error] = "#{k.capitalize} is missing."
      redirect '/admin/email'
    end
  end

  sites = Site.newsletter_sites

  day = 0

  until sites.empty?
    seconds = 0.0
    queued_sites = []
    Site::EMAIL_BLAST_MAXIMUM_PER_DAY.times {
      break if sites.empty?
      queued_sites << sites.pop
    }

    queued_sites.each do |site|
      EmailWorker.perform_at((day.days.from_now + seconds), {
        from: Site::FROM_EMAIL,
        to: site.email,
        subject: params[:subject],
        body: params[:body]
      })
      seconds += 0.5
    end

    day += 1
  end

  flash[:success] = "#{sites.length} emails have been queued, #{Site::EMAIL_BLAST_MAXIMUM_PER_DAY} per day."
  redirect '/'
end

post '/admin/ban' do
  require_admin
  if params[:usernames].empty?
    flash[:error] = 'no usernames provided'
    redirect request.referrer
  end

  usernames = params[:usernames].split("\n").collect {|u| u.strip}

  deleted_count = 0
  ip_deleted_count = 0

  usernames.each do |username|
    next if username == ''
    site = Site[username: username]
    next if site.nil? || site.is_banned

    if !params[:classifier].empty?
      site.untrain 'index.html'
      site.train 'index.html', params[:classifier]
    end

    site.ban!
    deleted_count += 1

    if !params[:ban_using_ips].empty? && IPAddress.valid?(site.ip)
      sites = Site.filter(ip: site.ip, is_banned: false).all
      sites.each do |s|
        next if usernames.include?(s.username)
        s.ban!
      end
      ip_deleted_count += 1
    end

    if params[:classifier] == 'spam' || params[:classifier] == 'phishing'
      next unless IPAddress.valid?(site.ip)
      StopForumSpamWorker.perform_async(
        username: site.username,
        email: site.email,
        ip: site.ip,
        classifier: params[:classifier]
      )
    end
  end

  flash[:success] = "#{ip_deleted_count + deleted_count} sites have been banned, including #{ip_deleted_count} matching IPs."
  redirect request.referrer
end

post '/admin/unban' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect request.referrer
  end

  if !site.is_banned
    flash[:error] = 'Site is not banned'
    redirect request.referrer
  end

  site.unban!

  flash[:success] = "Site #{site.username} was unbanned."
  redirect request.referrer
end

post '/admin/mark_nsfw' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect request.referrer
  end

  site.is_nsfw = true
  site.admin_nsfw = true
  site.save_changes validate: false

  flash[:success] = 'MISSION ACCOMPLISHED'
  redirect request.referrer
end

post '/admin/unmark_nsfw' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect request.referrer
  end

  site.is_nsfw = false
  site.admin_nsfw = false
  site.save_changes validate: false

  flash[:success] = 'Site unmarked as NSFW'
  redirect request.referrer
end

post '/admin/feature' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect request.referrer
  end

  site.featured_at = Time.now
  site.save_changes(validate: false)
  flash[:success] = 'Site has been featured.'
  redirect request.referrer
end

post '/admin/verify_email' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect request.referrer
  end

  if site.email_confirmed
    flash[:error] = 'Email is already confirmed'
    redirect request.referrer
  end

  site.email_confirmed = true
  site.save_changes(validate: false)
  flash[:success] = "Email for #{site.username} has been manually verified."
  redirect request.referrer
end

get '/admin/masquerade/:username' do
  require_admin
  site = Site[username: params[:username]]
  not_found if site.nil?
  session[:id] = site.id
  redirect '/'
end

get '/admin/site/:username_or_email' do
  require_admin
  ident = params[:username_or_email]

  if ident.blank?
    flash[:error] = 'username or email required'
    redirect '/admin'
  end

  if ident =~ /@/
    @site = Site[email: ident]
  else
    @site = Site[username: ident]
  end

  if @site.nil?
    flash[:error] = "site not found"
    redirect request.referrer
  end

  @title = "Site Info - #{@site.username}"

  erb :'admin/site'
end