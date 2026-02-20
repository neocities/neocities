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

  # Dismiss any other reports for the site
  DB[:reports].where(site_id: report.site_id).destroy

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
  start_month = Date.new(2016, 2, 1)

  # Build date range for batch query
  months = []
  month = current_month
  until month < start_month
    months << month
    month = month.prev_month
  end

  # Batch query for all monthly stats at once using proper date comparisons
  monthly_stats_query = <<-SQL
    SELECT
      DATE_TRUNC('month', created_at) as month,
      SUM(views) as views,
      SUM(hits) as hits,
      SUM(bandwidth) as bandwidth
    FROM daily_site_stats
    WHERE created_at >= ?
      AND created_at <= ?
    GROUP BY DATE_TRUNC('month', created_at)
    ORDER BY month DESC
  SQL

  monthly_data = DB[monthly_stats_query, start_month, current_month.next_month].all

  # Convert to hash for easy lookup
  stats_by_month = {}
  monthly_data.each do |row|
    month_key = row[:month].to_date
    stats_by_month[month_key] = {
      views: row[:views] || 0,
      hits: row[:hits] || 0,
      bandwidth: row[:bandwidth] || 0
    }
  end

  # Batch query for all popular sites data at once
  popular_sites_query = <<-SQL
    SELECT
      DATE_TRUNC('month', stats.created_at) as month,
      sites.username,
      SUM(stats.bandwidth) as bandwidth
    FROM stats
    LEFT JOIN sites ON sites.id = stats.site_id
    WHERE stats.created_at >= ?
      AND stats.created_at <= ?
      AND sites.username IS NOT NULL
    GROUP BY DATE_TRUNC('month', stats.created_at), sites.username
  SQL

  all_popular_sites = DB[popular_sites_query, start_month, current_month.next_month].all

  # Group popular sites by month and get top 50 for each
  popular_by_month = {}
  all_popular_sites.group_by { |row| row[:month].to_date }.each do |month_key, sites|
    popular_by_month[month_key] = sites
      .sort_by { |s| -(s[:bandwidth] || 0) }
      .take(50)
      .map { |s| { username: s[:username], bandwidth: s[:bandwidth] } }
  end

  # Combine the results
  @monthly_stats = []
  months.each do |month|
    stats = stats_by_month[month]
    next unless stats && stats[:views] != 0 && stats[:hits] != 0 && stats[:bandwidth] != 0

    @monthly_stats.push({
      views: stats[:views],
      hits: stats[:hits],
      bandwidth: stats[:bandwidth],
      date: month,
      popular_sites: popular_by_month[month] || []
    })
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

post '/admin/mark_moderated' do
  require_admin

  not_found if params[:site_id].blank?
  site = Site[params[:site_id]]
  not_found if site.nil?

  site_ids = Site.moderation_dataset.select(:id).where{created_at <= site.created_at}.all.collect {|s| s.id}

  DB[:sites].where(id: site_ids).update(needs_moderation: false)

  remaining_ds = Site.moderation_dataset.order(:created_at.desc)
  remaining_ds = remaining_ds.paginate(1, Site::BROWSE_PAGINATION_LENGTH)
  last_page = remaining_ds.page_count
  last_page = 1 if last_page < 1

  uri = Addressable::URI.parse request.referer
  query = Rack::Utils.parse_query uri.query
  query['page'] = last_page.to_s
  uri.query = Rack::Utils.build_query(query)
  redirect uri.to_s
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

get %r{/admin/site/(.+)} do |username_or_email_or_domain|
  require_admin
  ident = request.path_info.sub(%r{\A/admin/site/}, '')

  if ident.blank?
    flash[:error] = 'username or email or domain required'
    redirect '/admin'
  end

  ident = ident.to_s.strip
  ident = ident.sub(%r{\A(https?):/+}, '\1://')

  begin
    parsed_ident = Addressable::URI.parse(ident)
    ident = parsed_ident.host if parsed_ident.host
  rescue Addressable::URI::InvalidURIError
  end

  ident = ident.split('/').first.to_s.downcase

  if ident =~ /@/
    @site = Site[email: ident]
  elsif ident.end_with?('.neocities.org')
    @site = Site[username: ident.sub(/\.neocities\.org\z/, '')]
  elsif ident =~ /.+\..+$/
    @site = Site.where(domain: ident).first
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
