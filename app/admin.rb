get '/admin' do
  require_admin
  @banned_sites = Site.select(:username).filter(is_banned: true).order(:username).all
  @nsfw_sites = Site.select(:username).filter(is_nsfw: true).order(:username).all
  erb :'admin'
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
    queued_sites = []
    Site::EMAIL_BLAST_MAXIMUM_PER_DAY.times {
      break if sites.empty?
      queued_sites << sites.pop
    }

    queued_sites.each do |site|
      EmailWorker.perform_at(day.days.from_now, {
        from: 'noreply@neocities.org',
        to: site.email,
        subject: params[:subject],
        body: params[:body]
      })
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
  sites = Site.filter(ip: Site.hash_ip(site.ip), is_banned: false).all
  sites.each {|s| s.ban!}
  flash[:error] = "#{sites.length} sites have been banned."
  redirect '/admin'
end

post '/admin/banhammer' do
  require_admin

  site = Site[username: params[:username]]

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
