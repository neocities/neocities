get '/admin' do
  require_admin
  @banned_sites = Site.select(:username).filter(is_banned: true).order(:username).all
  @nsfw_sites = Site.select(:username).filter(is_nsfw: true).order(:username).all
  erb :'admin'
end

get '/admin/reports' do
  require_admin
  @reports = Report.order(:created_at.desc).all
  erb :'admin/reports'
end

get '/admin/site/:username' do |username|
  require_admin
  @site = Site[username: username]
  not_found if @site.nil?
  @title = "Site Inspector - #{@site.username}"
  erb :'admin/site'
end

post '/admin/reports' do

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
    monthly_stats.push(
      date: runner,
      sites_created: Site.where(created_at: runner..runner.next_month).count,
      total_from_start: Site.where(created_at: start..runner.next_month).count,
      supporters: Site.where(created_at: start..runner.next_month).exclude(stripe_customer_id: nil).count,
    )

    runner = runner.next_month
  end

  @stats[:monthly_stats] = monthly_stats

  if $stripe_cache && Time.now < $stripe_cache[:time] + 14400
    customers = $stripe_cache[:customers]
  else
    customers = Stripe::Customer.all limit: 100000
    $stripe_cache = {
      customers: customers,
      time: Time.now
    }
  end

  @stats[:monthly_revenue] = 0.0

  subscriptions = []
  @stats[:cancelled_subscriptions] = 0

  customers.each do |customer|
    sub = {created_at: Time.at(customer.created)}

    if customer[:subscriptions][:data].empty?
      @stats[:cancelled_subscriptions] += 1
      next
    end

    next if customer[:subscriptions][:data].first[:plan][:amount] == 0

    sub[:status] = 'active'
    plan = customer[:subscriptions][:data].first[:plan]

    sub[:amount_without_fees] = (plan[:amount] / 100.0).round(2)
    sub[:percentage_fee] = (sub[:amount_without_fees]/(100/2.9)).ceil_to(2)
    sub[:fixed_fee] = 0.30
    sub[:amount] = sub[:amount_without_fees] - sub[:percentage_fee] - sub[:fixed_fee]

    if(plan[:interval] == 'year')
      sub[:amount] = (sub[:amount] / 12).round(2)
    end

    @stats[:monthly_revenue] += sub[:amount]

    subscriptions.push sub
  end

  @stats[:subscriptions] = subscriptions

  # Hotwired for now
  @stats[:expenses] = 300.0 #/mo
  @stats[:percent_until_profit] = (
    (@stats[:monthly_revenue].to_f / @stats[:expenses]) * 100
  )

  @stats[:poverty_threshold] = 11_945
  @stats[:poverty_threshold_percent] = (@stats[:monthly_revenue].to_f / ((@stats[:poverty_threshold]/12) + @stats[:expenses])) * 100

  # http://en.wikipedia.org/wiki/Poverty_threshold

  @stats[:average_developer_salary] = 93_280.00 # google "average developer salary"
  @stats[:percent_until_developer_salary] = (@stats[:monthly_revenue].to_f / ((@stats[:average_developer_salary]/12) + @stats[:expenses])) * 100

  erb :'admin/stats'
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
        from: 'Kyle from Neocities <kyle@neocities.org>',
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

post '/admin/banhammer' do
  require_admin

  if params[:usernames].empty?
    flash[:error] = 'no usernames provided'
    redirect '/admin'
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
  redirect '/admin'
end

post '/admin/mark_nsfw' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  site.is_nsfw = true
  site.admin_nsfw = true
  site.save_changes validate: false

  flash[:success] = 'MISSION ACCOMPLISHED'
  redirect '/admin'
end

post '/admin/feature' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  site.featured_at = Time.now
  site.save_changes(validate: false)
  flash[:success] = 'Site has been featured.'
  redirect '/admin'
end

get '/admin/masquerade/:username' do
  require_admin
  site = Site[username: params[:username]]
  not_found if site.nil?
  session[:id] = site.id
  redirect '/'
end

def require_admin
  redirect '/' unless is_admin?
end

def is_admin?
  signed_in? && current_site.is_admin
end