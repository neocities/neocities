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

  until month.year == 2015 && month.month == 1 do
    stats = DB[
      'select sum(views) as views, sum(hits) as hits, sum(bandwidth) as bandwidth from stats where created_at >= ? and created_at < ?',
      month,
      month.next_month].first

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

post '/admin/banip' do
  require_admin
  site = Site[username: params[:username]]

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  if site.ip.nil? || site.ip.empty?
    flash[:error] = 'IP is blank, cannot continue'
    redirect '/admin'
  end
  sites = Site.filter(ip: site.ip, is_banned: false).all
  sites.each {|s| s.ban!}
  flash[:error] = "#{sites.length} sites have been banned."
  redirect '/admin'
end

post '/admin/banhammer' do
  require_admin

  site = Site[username: params[:username]]

  if !params[:classifier].empty?
    site.untrain 'index.html'
    site.train 'index.html', params[:classifier]
  end

  if site.nil?
    flash[:error] = 'User not found'
    redirect '/admin'
  end

  if site.is_banned
    flash[:error] = 'User is already banned'
    redirect '/admin'
  end

  site.ban!

  flash[:success] = 'MISSION ACCOMPLISHED'
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

def require_admin
  redirect '/' unless signed_in? && current_site.is_admin
end
