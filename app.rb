require 'base64'
require 'uri'
require 'net/http'
require './environment.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

use Rack::Recaptcha, public_key: $config['recaptcha_public_key'], private_key: $config['recaptcha_private_key']
helpers Rack::Recaptcha::Helpers

helpers do
  def site_change_file_display_class(filename)
    return 'html' if filename.match(Site::HTML_REGEX)
    return 'image' if filename.match(Site::IMAGE_REGEX)
    'misc'
  end

  def csrf_token_input_html
    %{<input name="csrf_token" type="hidden" value="#{csrf_token}">}
  end
end

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/stripe_webhook$/
    # Skips the CSRF check for stripe web hooks
  else
    content_type :html, 'charset' => 'utf-8'
    redirect '/' if request.post? && !csrf_safe?
  end
end

not_found do
  erb :'not_found'
end

error do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: "#{request.request_method} #{request.path}\n\n" +
          (current_site ? "Site: #{current_site.username}\nEmail: #{current_site.email}\n\n" : '') +
          env['sinatra.error'].backtrace.join("\n")
  })

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

# :nocov:
get '/home_mockup' do
  erb :'home_mockup'
end

get '/edit_mockup' do
  erb :'edit_mockup'
end

get '/profile_mockup' do
  require_login
  erb :'profile_mockup', locals: {site: current_site}
end

get '/browse_mockup' do
  erb :'browse_mockup'
end

get '/tips_mockup' do
  erb :'tips_mockup'
end
# :nocov:

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
  current_site.update editor_theme: params[:editor_theme]
  'ok'
end

post '/settings/create_child' do
  require_login
  site = Site.new

  site.parent_site_id = parent_site.id
  site.username = params[:username]

  if site.valid?
    site.save
    flash[:success] = 'Your new site has been created! To manage it, click your username in the top right and go to "Switch Site".'
    redirect '/settings#sites'
  else
    flash[:error] = site.errors.first.last.first
    redirect '/settings#sites'
  end
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

get '/stats/?' do
  require_admin

  @stats = {
    total_sites: Site.count,
    total_unbanned_sites: Site.where(is_banned: false).count,
    total_banned_sites: Site.where(is_banned: true).count,
    total_nsfw_sites: Site.where(is_nsfw: true).count,
    total_unbanned_nsfw_sites: Site.where(is_banned: false, is_nsfw: true).count,
    total_banned_nsfw_sites: Site.where(is_banned: true, is_nsfw: true).count
  }

  # Start with the date of the first created site

  start = Site.select(:created_at).
               exclude(created_at: nil).
               order(:created_at).
               first[:created_at].to_date

  runner = start

  monthly_stats = []

  now = Time.now

  until runner.year == now.year && runner.month == now.month+1
    monthly_stats.push(
      date: runner,
      sites_created: Site.where(created_at: runner..runner.next_month).count,
      total_from_start: Site.where(created_at: start..runner.next_month).count,
      supporters: Site.where(created_at: start..runner.next_month).exclude(stripe_customer_id: nil).count,
    )

    runner = runner.next_month
  end

  @stats[:monthly_stats] = monthly_stats

  customers = Stripe::Customer.all

  @stats[:total_recurring_revenue] = 0.0

  subscriptions = []
  cancelled_subscriptions = 0

  customers.each do |customer|
    sub = {created_at: Time.at(customer.created)}
    if customer[:subscriptions]
      if customer[:subscriptions][:data].empty?
        sub[:status] = 'cancelled'
      else
        sub[:status] = 'active'
        sub[:amount] = (customer[:subscriptions][:data].first[:plan][:amount] / 100.0).round(2)
        @stats[:total_recurring_revenue] += sub[:amount]
      end
    end
    subscriptions.push sub
  end

  @stats[:subscriptions] = subscriptions
  erb :'stats'
end

get '/?' do
  if current_site
    require_login

    @suggestions = current_site.suggestions

    @current_page = params[:current_page].to_i
    @current_page = 1 if @current_page == 0

    if params[:activity] == 'mine'
      events_dataset = current_site.latest_events(@current_page, 10)
    elsif params[:event_id]
      event = Event.select(:id).where(id: params[:event_id]).first
      not_found if event.nil?
      events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
    else
      events_dataset = current_site.news_feed(@current_page, 10)
    end

    @page_count = events_dataset.page_count || 1
    @events = events_dataset.all

    current_site.events_dataset.update notification_seen: true

    halt erb :'home', locals: {site: current_site}
  end

  if SimpleCache.expired?(:sites_count)
    @sites_count = SimpleCache.store :sites_count, Site.count.roundup(100), 600 # 10 Minutes
  else
    @sites_count = SimpleCache.get :sites_count
  end

  @blackbox_question = BlackBox.generate
  @question_first_number, @question_last_number = generate_question

  erb :index, layout: false
end

def generate_question
  if ENV['RACK_ENV'] == 'test'
    question_first_number = 1
    question_last_number = 1
  else
    question_first_number = rand 5
    question_last_number = rand 5
  end
  session[:question_answer] = (question_first_number + question_last_number).to_s
  [question_first_number, question_last_number]
end

get '/plan/?' do
  @title = 'Support Us'

  if parent_site && parent_site.unconverted_legacy_supporter?
    customer = Stripe::Customer.retrieve(parent_site.stripe_customer_id)
    subscription = customer.subscriptions.first
    parent_site.stripe_subscription_id = subscription.id
    parent_site.plan_type = subscription.plan.id
    parent_site.save_changes
  end

  erb :'plan/index'
end

post '/plan/update' do
  require_login

  DB.transaction do
    if parent_site.stripe_subscription_id
      customer = Stripe::Customer.retrieve parent_site.stripe_customer_id
      subscription = customer.subscriptions.retrieve parent_site.stripe_subscription_id
      subscription.plan = params[:plan_type]
      subscription.save

      parent_site.update(
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    else
      customer = Stripe::Customer.create(
        card: params[:stripe_token],
        description: "#{parent_site.username} - #{parent_site.id}",
        email: (current_site.email || parent_site.email),
        plan: params[:plan_type]
      )

      parent_site.update(
        stripe_customer_id: customer.id,
        stripe_subscription_id: customer.subscriptions.first.id,
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    end
  end

  if current_site.email || parent_site.email
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      reply_to: 'contact@neocities.org',
      to: current_site.email || parent_site.email,
      subject: "[Neocities] You've become a supporter!",
      body: Tilt.new('./views/templates/email_subscription.erb', pretty: true).render(self, plan_name: Site::PLAN_FEATURES[params[:plan_type].to_sym][:name], plan_space: Site::PLAN_FEATURES[params[:plan_type].to_sym][:space].to_space_pretty)
    })
  end

  redirect params[:plan_type] == 'free' ? '/plan' : '/plan/thanks'
end

get '/plan/thanks' do
  require_login
  erb :'plan/thanks'
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

post '/tags/add' do
  require_login
  current_site.new_tags_string = params[:tags]

  if current_site.valid?
    current_site.save_tags
  else
    flash[:errors] = current_site.errors.first
  end

  redirect request.referer
end

post '/tags/remove' do
  require_login

  DB.transaction {
    params[:tags].each {|tag| current_site.remove_tag Tag[name: tag]}
  }

  redirect request.referer
end

get '/tags/autocomplete/:name.json' do |name|
  Tag.autocomplete(name).collect {|t| t[:name]}.to_json
end

def browse_sites_dataset
  @current_page = params[:current_page]
  @current_page = @current_page.to_i
  @current_page = 1 if @current_page == 0

  site_dataset = Site.filter(is_banned: false, is_crashing: false).filter(site_changed: true)

  if current_site
    if !current_site.blocking_site_ids.empty?
      site_dataset.where!(Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocking_site_ids))
    end

    if current_site.blocks_dataset.count
      site_dataset.where!(
        Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocks_dataset.select(:actioning_site_id).all.collect {|s| s.actioning_site_id})
      )
    end
  end

  case params[:sort_by]
    when 'hits'
      site_dataset.order!(:hits.desc, :site_updated_at.desc)
    when 'views'
      site_dataset.order!(:views.desc, :site_updated_at.desc)
    when 'newest'
      site_dataset.order!(:created_at.desc, :views.desc)
    when 'oldest'
      site_dataset.order!(:created_at, :views.desc)
    when 'random'
      site_dataset.where! 'random() < 0.01'
    when 'last_updated'
      params[:sort_by] = 'last_updated'
      site_dataset.order!(:site_updated_at.desc, :views.desc)
    else
      if params[:tag]
        params[:sort_by] = 'views'
        site_dataset.order!(:views.desc, :site_updated_at.desc)
      else
        params[:sort_by] = 'last_updated'
        site_dataset.order!(:site_updated_at.desc, :views.desc)
      end
  end

  site_dataset.where! ['sites.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]

  if params[:tag]
    site_dataset = site_dataset.association_join(:tags).select_all(:sites)
    site_dataset.where! ['tags.name = ?', params[:tag]]
    site_dataset.where! ['tags.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]
  end

  site_dataset
end

get '/browse/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, 300
  @page_count = site_dataset.page_count || 1
  @sites = site_dataset.all
  erb :browse
end

get '/surf/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, 1
  @page_count = site_dataset.page_count || 1
  @site = site_dataset.first
  redirect "/browse?#{Rack::Utils.build_query params}" if @site.nil?
  erb :'surf', layout: false
end

get '/surf/:username' do |username|
  @site = Site.select(:id, :username, :title, :domain, :views, :stripe_customer_id).where(username: username).first
  @title = @site.title
  not_found if @site.nil?
  erb :'surf', layout: false
end

get '/api' do
  @title = 'Developers API'
  erb :'api'
end

get '/tutorials' do
  erb :'tutorials'
end

get '/donate' do
  erb :'donate'
end

get '/blog' do
  expires 500, :public, :must_revalidate
  return Net::HTTP.get_response(URI('http://blog.neocities.org')).body
end

get '/blog/:article' do |article|
  expires 500, :public, :must_revalidate
  return Net::HTTP.get_response(URI("http://blog.neocities.org/#{article}.html")).body
end

get '/new' do
  dashboard_if_signed_in
  require_unbanned_ip
  @site = Site.new
  @site.username = params[:username] unless params[:username].nil?
  erb :'new'
end

post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match /^username$|^password$|^email$|^new_tags_string$/}

  site = Site.new fields
  return [].to_json if site.valid?
  site.errors.collect {|e| [e.first, e.last.first]}.to_json
end

post '/create_validate' do
  content_type :json

  if !params[:field].match /^username$|^password$|^email$|^new_tags_string$/
    return {error: 'not a valid field'}.to_json
  end  

  site = Site.new(params[:field] => params[:value])
  site.valid?

  field_sym = params[:field].to_sym

  if site.errors[field_sym]
    return {error: site.errors[field_sym].first}.to_json
  end

  {result: 'ok'}.to_json
end

post '/create' do
  content_type :json
  require_unbanned_ip
  dashboard_if_signed_in

  @site = Site.new(
    username: params[:username],
    password: params[:password],
    email: params[:email],
    new_tags_string: params[:tags],
    ip: request.ip
  )

  black_box_answered = BlackBox.valid? params[:blackbox_answer], request.ip
  question_answered_correctly = params[:question_answer] == session[:question_answer]

  if !question_answered_correctly
    question_first_number, question_last_number = generate_question
    return {
      result: 'bad_answer',
      question_first_number: question_first_number,
      question_last_number: question_last_number
    }.to_json
  end

  if !black_box_answered || !@site.valid? || Site.ip_create_limit?(request.ip)
    flash[:error] = 'There was an unknown error, please try again.'
    return {result: 'error'}.to_json
  end

  @site.save

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'contact@neocities.org',
    to: @site.email,
    subject: "[Neocities] Welcome to Neocities!",
    body: Tilt.new('./views/templates/email_welcome.erb', pretty: true).render(self)
  })

  send_confirmation_email @site

  session[:id] = @site.id
  {result: 'ok'}.to_json
end

get '/dashboard' do
  require_login

  if params[:dir] && params[:dir][0] != '/'
    params[:dir] = '/'+params[:dir]
  end

  if !File.directory?(current_site.files_path(params[:dir]))
    redirect '/dashboard'
  end

  @dir = params[:dir]
  @file_list = current_site.file_list @dir
  erb :'dashboard'
end

get '/settings/?' do
  require_login
  @site = parent_site
  erb :'settings/account'
end

def require_ownership_for_settings
  @site = Site[username: params[:username]]

  not_found if @site.nil?

  unless @site.owned_by? parent_site
    flash[:error] = 'Cannot edit this site, you do not have permission.'
    redirect request.referrer
  end
end

get '/settings/:username/?' do
  require_login
  require_ownership_for_settings
  erb :'settings/site'
end

post '/settings/:username/profile' do
  require_login
  require_ownership_for_settings

  @site.update(
    profile_comments_enabled: params[:site][:profile_comments_enabled]
  )
  flash[:success] = 'Profile settings changed.'
  redirect "/settings/#{@site.username}#profile"
end

post '/settings/:username/ssl' do
  require_login
  require_ownership_for_settings

  unless params[:key] && params[:cert]
    flash[:error] = 'SSL key and certificate are required.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  begin
    key = OpenSSL::PKey::RSA.new params[:key][:tempfile].read, ''
  rescue => e
    flash[:error] = 'Could not process SSL key, file may be incorrect, damaged, or passworded (you need to remove the password).'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  if !key.private?
    flash[:error] = 'SSL Key file does not have private key data.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  certs_string = params[:cert][:tempfile].read

  cert_array = certs_string.lines.slice_before(/-----BEGIN CERTIFICATE-----/).to_a.collect {|a| a.join}

  if cert_array.empty?
    flash[:error] = 'Cert file does not contain any certificates.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  cert_valid_for_domain = false

  cert_array.each do |cert_string|
    begin
      cert = OpenSSL::X509::Certificate.new cert_string
    rescue => e
      flash[:error] = 'Could not process SSL certificate, file may be incorrect or damaged.'
      redirect "/settings/#{@site.username}#custom_domain"
    end

    if cert.not_after < Time.now
      flash[:error] = 'SSL Certificate has expired, please create a new one.'
      redirect "/settings/#{@site.username}#custom_domain"
    end

    cert_cn = cert.subject.to_a.select {|a| a.first == 'CN'}.flatten[1]
    cert_valid_for_domain = true if cert_cn && cert_cn.match(@site.domain)
  end

  unless cert_valid_for_domain
    flash[:error] = "Your certificate CN (common name) does not match your domain: #{@site.domain}"
    redirect "/settings/#{@site.username}#custom_domain"
  end

  # Everything else was worse.

  crtfile = Tempfile.new 'crtfile'
  crtfile.write cert_array.join
  crtfile.close

  keyfile = Tempfile.new 'keyfile'
  keyfile.write key.to_pem
  keyfile.close

  if ENV['TRAVIS'] != 'true'
    nginx_testfile = Tempfile.new 'nginx_testfile'
    nginx_testfile.write %{
      pid /tmp/throwaway.pid;
      events {}
      error_log /dev/null error;
      http {
        access_log off;
        server {
          listen 60000 ssl;
          server_name #{@site.domain} *.#{@site.domain};
          ssl_certificate #{crtfile.path};
          ssl_certificate_key #{keyfile.path};
        }
      }
    }
    nginx_testfile.close

    line = Cocaine::CommandLine.new(
      "nginx", "-t -c :path",
      expected_outcodes: [0],
      swallow_stderr: true
    )

    begin
      output = line.run path: nginx_testfile.path
    rescue Cocaine::ExitStatusError => e
      flash[:error] = "There is something wrong with your certificate, please check with your issuing CA."
      redirect "/settings/#{@site.username}#custom_domain"
    end
  end

  @site.update ssl_key: key.to_pem, ssl_cert: cert_array.join

  flash[:success] = 'Updated SSL key/certificate.'
  redirect "/settings/#{@site.username}#custom_domain"
end

post '/settings/:username/change_name' do
  require_login
  require_ownership_for_settings

  old_username = @site.username

  if params[:name] == nil || params[:name] == ''
    flash[:error] = 'Name cannot be blank.'
    redirect "/settings/#{@site.username}#username"
  end

  if old_username == params[:name]
    flash[:error] = 'You already have this name.'
    redirect "/settings/#{@site.username}#username"
  end

  old_host = @site.host
  old_file_paths = @site.file_list.collect {|f| f[:path]}

  @site.username = params[:name]

  if @site.valid?
    DB.transaction {
      @site.save_changes
      @site.move_files_from old_username
    }

    old_file_paths.each do |file_path|
      @site.purge_cache file_path
    end

    flash[:success] = "Site/user name has been changed. You will need to use this name to login, <b>don't forget it</b>."
    redirect "/settings/#{@site.username}#username"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{old_username}#username"
  end
end

post '/settings/:username/change_nsfw' do
  require_login
  require_ownership_for_settings

  @site.update is_nsfw: params[:is_nsfw]
  flash[:success] = @site.is_nsfw ? 'Marked 18+' : 'Unmarked 18+'
  redirect "/settings/#{@site.username}#nsfw"
end

post '/settings/:username/custom_domain' do
  require_login
  require_ownership_for_settings

  @site.domain = params[:domain]

  if @site.valid?
    @site.save_changes
    flash[:success] = 'The domain has been successfully updated.'
    redirect "/settings/#{@site.username}#custom_domain"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{@site.username}#custom_domain"
  end
end

post '/settings/change_password' do
  require_login

  if !Site.valid_login?(parent_site.username, params[:current_password])
    flash[:error] = 'Your provided password does not match the current one.'
    redirect "/settings#password"
  end

  parent_site.password = params[:new_password]
  parent_site.valid?

  if params[:new_password] != params[:new_password_confirm]
    parent_site.errors.add :password, 'New passwords do not match.'
  end

  if parent_site.errors.empty?
    parent_site.save_changes
    flash[:success] = 'Successfully changed password.'
    redirect "/settings#password"
  else
    flash[:error] = current_site.errors.first.last.first
    redirect '/settings#password'
  end
end

post '/settings/change_email' do
  require_login
  
  if params[:email] == parent_site.email
    flash[:error] = 'You are already using this email address for this account.'
    redirect '/settings#email'
  end

  parent_site.email = params[:email]
  parent_site.email_confirmation_token = SecureRandom.hex 3
  parent_site.email_confirmed = false

  if parent_site.valid?
    parent_site.save_changes
    send_confirmation_email
    flash[:success] = 'Successfully changed email. We have sent a confirmation email, please use it to confirm your email address.'
    redirect '/settings#email'
  end

  flash[:error] = parent_site.errors.first.last.first
  redirect '/settings#email'
end

get '/password_reset' do
  erb :'password_reset'
end

post '/send_password_reset' do
  sites = Site.filter(email: params[:email]).all

  if sites.length > 0
    token = SecureRandom.uuid.gsub('-', '')
    sites.each do |site|
      site.update password_reset_token: token
    end

    body = <<-EOT
Hello! This is the Neocities cat, and I have received a password reset request for your e-mail address. Purrrr.

Go to this URL to reset your password: http://neocities.org/password_reset_confirm?token=#{token}

After clicking on this link, your password for all the sites registered to this email address will be changed to this token.

Token: #{token}

If you didn't request this reset, you can ignore it. Or hide under a bed. Or take a nap. Your call.

Meow,
the Neocities Cat
    EOT

    body.strip!

    EmailWorker.perform_async({
      from: 'web@neocities.org',
      to: params[:email],
      subject: '[Neocities] Password Reset',
      body: body
    })
  end

  flash[:success] = 'If your email was valid (and used by a site), the Neocities Cat will send an e-mail to your account with password reset instructions.'
  redirect '/'
end

get '/password_reset_confirm' do
  if params[:token].nil? || params[:token].empty?
    flash[:error] = 'Could not find a site with this token.'
    redirect '/'
  end

  reset_site = Site[password_reset_token: params[:token]]

  if reset_site.nil?
    flash[:error] = 'Could not find a site with this token.'
    redirect '/'
  end

  sites = Site.filter(email: reset_site.email).all

  if sites.length > 0
    sites.each do |site|
      site.password = reset_site.password_reset_token
      site.save_changes
    end

    flash[:success] = 'Your password for all sites with your email address has been changed to the token sent in your e-mail. Please login and change your password as soon as possible.'
  else
    flash[:error] = 'Could not find a site with this token.'
  end

  redirect '/'
end

get '/signin/?' do
  dashboard_if_signed_in
  erb :'signin'
end

post '/signin' do
  dashboard_if_signed_in

  if Site.valid_login? params[:username], params[:password]
    site = Site.get_with_identifier params[:username]

    if site.is_banned
      flash[:error] = 'Invalid login.'
      flash[:username] = params[:username]
      redirect '/signin'
    end

    session[:id] = site.id
    redirect '/'
  else
    flash[:error] = 'Invalid login.'
    flash[:username] = params[:username]
    redirect '/signin'
  end
end

get '/signout' do
  require_login
  session[:id] = nil
  redirect '/'
end

get '/signin/:username' do
  require_login
  @site = Site[username: params[:username]]

  not_found if @site.nil?

  if @site.owned_by? current_site
    session[:id] = @site.id
    redirect request.referrer
  end

  flash[:error] = 'You do not have permission to switch to this site.'
  redirect request.referrer
end

get '/about' do
  erb :'about'
end

get '/site_files/new_page' do
  require_login
  erb :'site_files/new_page'
end

post '/site_files/create_page' do
  require_login
  @errors = []

  params[:pagefilename].gsub!(/[^a-zA-Z0-9_\-.]/, '')
  params[:pagefilename].gsub!(/\.html$/i, '')

  if params[:pagefilename].nil? || params[:pagefilename].empty?
    @errors << 'You must provide a file name.'
    halt erb(:'site_files/new_page')
  end

  name = "#{params[:pagefilename]}.html"

  name = "#{params[:dir]}/#{name}" if params[:dir]

  if current_site.file_exists?(name)
    @errors << %{Web page "#{name}" already exists! Choose another name.}
    halt erb(:'site_files/new_page')
  end

  current_site.install_new_html_file name

  flash[:success] = %{#{name} was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/#{name}">Click here to edit it</a>.}

  redirect params[:dir] ? "/dashboard?dir=#{Rack::Utils.escape params[:dir]}" : '/dashboard'
end

get '/site_files/new' do
  require_login
  erb :'site_files/new'
end

def file_upload_response(error=nil)
  http_error_code = 406

  if params[:from_button]
    if error
      @error = error
      halt 200, erb(:'dashboard')
    else
      query_string = params[:dir] ? "?"+Rack::Utils.build_query(dir: params[:dir]) : ''
      redirect "/dashboard#{query_string}"
    end
  else
    halt http_error_code, error if error
    halt 200, 'File(s) successfully uploaded.'
  end
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

post '/site_files/upload' do
  require_login
  @errors = []
  http_error_code = 406

  if params[:files].nil?
    file_upload_response "Uploaded files were not seen by the server, cancelled. We don't know what's causing this yet. Please contact us so we can help fix it. Thanks!"
  end

  params[:files].each do |file|
    file[:filename] = "#{params[:dir]}/#{file[:filename]}" if params[:dir]
    if current_site.file_size_too_large? file[:tempfile].size
      file_upload_response "#{params[:dir]}/#{file[:filename]} is too large, upload cancelled."
    end
    if !Site.valid_file_type? file
      file_upload_response "#{params[:dir]}/#{file[:filename]}: file type (or content in file) is not allowed on Neocities, upload cancelled."
    end
  end

  uploaded_size = params[:files].collect {|f| f[:tempfile].size}.inject{|sum,x| sum + x }

  if current_site.file_size_too_large? uploaded_size
    file_upload_response "File(s) do not fit in your available space, upload cancelled."
  end

  results = []
  params[:files].each do |file|
    results << current_site.store_file(file[:filename], file[:tempfile])
  end
  current_site.increment_changed_count if results.include?(true)

  file_upload_response
end

post '/site_files/delete' do
  require_login
  current_site.delete_file params[:filename]

  flash[:success] = "Deleted #{params[:filename]}."
  redirect '/dashboard'
end

get '/site_files/:username.zip' do |username|
  require_login
  zipfile_path = current_site.files_zip
  content_type 'application/octet-stream'
  attachment   "neocities-#{current_site.username}.zip"
  send_file zipfile_path
end

get '/site_files/download/:filename' do |filename|
  require_login
  content_type 'application/octet-stream'
  attachment filename
  current_site.get_file filename
end

get %r{\/site_files\/text_editor\/(.+)} do
  require_login
  @filename = params[:captures].first
  begin
    @file_data = current_site.get_file @filename
  rescue Errno::ENOENT
    flash[:error] = 'We could not find the requested file.'
    redirect '/dashboard'
  end
  erb :'site_files/text_editor'
end

post %r{\/site_files\/save\/(.+)} do
  require_login_ajax
  filename = params[:captures].first

  tempfile = Tempfile.new 'neocities_saving_file'

  input = request.body.read
  tempfile.set_encoding input.encoding
  tempfile.write input
  tempfile.close

  if current_site.file_size_too_large? tempfile.size
    halt 'File is too large to fit in your space, it has NOT been saved. You will need to reduce the size or upgrade to a new plan.'
  end

  current_site.store_file filename, tempfile

  'ok'
end

get '/site_files/allowed_types' do
  erb :'site_files/allowed_types'
end

get '/site_files/mount_info' do
  erb :'site_files/mount_info'
end

get '/terms' do
  erb :'terms'
end

get '/privacy' do
  erb :'privacy'
end

get '/press' do
  erb :'press'
end

get '/admin' do
  require_admin
  @banned_sites = Site.select(:username).filter(is_banned: true).order(:username).all
  @nsfw_sites = Site.select(:username).filter(is_nsfw: true).order(:username).all
  erb :'admin'
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

get '/contact' do
  erb :'contact'
end

post '/contact' do

  @errors = []

  if params[:email].empty? || params[:subject].empty? || params[:body].empty?
    @errors << 'Please fill out all fields'
  end

  if !recaptcha_valid?
    @errors << 'Captcha was not filled out (or was filled out incorrectly)'
  end

  if !@errors.empty?
    erb :'contact'
  else
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      reply_to: params[:email],
      to: 'contact@neocities.org',
      subject: "[Neocities Contact]: #{params[:subject]}",
      body: params[:body]
    })

    flash[:success] = 'Your contact has been sent.'
    redirect '/'
  end
end

post '/stripe_webhook' do
  event = JSON.parse request.body.read
  if event['type'] == 'customer.created'
    username  = event['data']['object']['description']
    email     = event['data']['object']['email']
  end
  'ok'
end

post '/api/upload' do
  require_api_credentials
  files = []
  params.each do |k,v|
    next unless v.is_a?(Hash) && v[:tempfile]
    path = k.to_s
    files << {filename: k || v[:filename], tempfile: v[:tempfile]}
  end

  api_error 400, 'missing_files', 'you must provide files to upload' if files.empty?

  uploaded_size = files.collect {|f| f[:tempfile].size}.inject{|sum,x| sum + x }

  if current_site.file_size_too_large? uploaded_size
    api_error 400, 'too_large', 'files are too large to fit in your space, try uploading smaller (or less) files'
  end

  files.each do |file|
    if !Site.valid_file_type?(file)
      api_error 400, 'invalid_file_type', "#{file[:filename]} is not a valid file type (or contains not allowed content), files have not been uploaded"
    end

    if File.directory? file[:filename]
      api_error 400, 'directory_exists', 'this name is being used by a directory, cannot continue'
    end
  end

  results = []
  files.each do |file|
    results << current_site.store_file(file[:filename], file[:tempfile])
  end

  current_site.increment_changed_count if results.include?(true)

  api_success 'your file(s) have been successfully uploaded'
end

post '/api/delete' do
  require_api_credentials

  api_error 400, 'missing_filenames', 'you must provide files to delete' if params[:filenames].nil? || params[:filenames].empty?

  paths = []
  params[:filenames].each do |path|
    unless path.is_a?(String)
      api_error 400, 'bad_filename', "#{path} is not a valid filename, canceled deleting"
    end

    if !current_site.file_exists?(path)
      api_error 400, 'missing_files', "#{path} was not found on your site, canceled deleting"
    end

    if path == 'index.html'
      api_error 400, 'cannot_delete_index', 'you cannot delete your index.html file, canceled deleting'
    end

    paths << path
  end

  paths.each do |path|
    current_site.delete_file(path)
  end

  api_success 'file(s) have been deleted'
end

get '/api/info' do
  if params[:sitename]
    site = Site[username: params[:sitename]]

    api_error 400, 'site_not_found', "could not find site #{params[:sitename]}" if site.nil? || site.is_banned
    api_success api_info_for(site)
  else
    init_api_credentials
    api_success api_info_for(current_site)
  end
end

def api_info_for(site)
  {
    info: {
      sitename: site.username,
      views: site.views,
      hits: site.hits,
      created_at: site.created_at.rfc2822,
      last_updated: site.site_updated_at ? site.site_updated_at.rfc2822 : nil,
      domain: site.domain,
      tags: site.tags.collect {|t| t.name}
    }
  }
end

# Catch-all for missing api calls

get '/api/:name' do
  api_not_found
end

post '/api/:name' do
  api_not_found
end

post '/event/:event_id/toggle_like' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  liked_response = event.toggle_site_like(current_site) ? 'liked' : 'unliked'
  {result: liked_response, event_like_count: event.likes_dataset.count, liking_site_names: event.liking_site_usernames}.to_json
end

post '/event/:event_id/comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]

  site = event.site

  if site.is_blocking?(current_site) ||
     site.profile_comments_enabled == false ||
     current_site.commenting_allowed? == false
    return {result: 'error'}.to_json
  end

  event.add_site_comment current_site, params[:message]
  {result: 'success'}.to_json
end

post '/event/:event_id/update_profile_comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  return {result: 'error'}.to_json unless current_site.id == event.profile_comment.actioning_site_id

  event.profile_comment.update message: params[:message]
  return {result: 'success'}.to_json
end

post '/event/:event_id/delete' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]

  if event.site_id == current_site.id || event.created_by?(current_site)
    event.delete
    return {result: 'success'}.to_json
  end

  return {result: 'error'}.to_json
end

post '/comment/:comment_id/toggle_like' do |comment_id|
  require_login
  content_type :json
  comment = Comment[id: comment_id]
  liked_response = comment.toggle_site_like(current_site) ? 'liked' : 'unliked'
  {result: liked_response, comment_like_count: comment.comment_likes_dataset.count, liking_site_names: comment.liking_site_usernames}.to_json
end

post '/comment/:comment_id/delete' do |comment_id|
  require_login
  content_type :json
  comment = Comment[id: comment_id]

  if comment.event.site == current_site || comment.actioning_site == current_site
    comment.delete
    return {result: 'success'}.to_json
  end

  return {result: 'error'}.to_json
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

def require_admin
  redirect '/' unless signed_in? && current_site.is_admin
end

def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def require_login_ajax
  halt 'You are not logged in!' unless signed_in?
  halt 'You are banned.' if current_site.is_banned? || parent_site.is_banned?
end

def csrf_safe?
  csrf_token == params[:csrf_token] || csrf_token == request.env['HTTP_X_CSRF_TOKEN']
end

def csrf_token
   session[:_csrf_token] ||= SecureRandom.base64(32)
end

def require_login
  redirect '/' unless signed_in?
  if session[:banned] || current_site.is_banned || parent_site.is_banned
    session[:id] = nil
    session[:banned] = true
    redirect '/'
  end
end

def signed_in?
  !session[:id].nil?
end

def current_site
  return nil if session[:id].nil?
  @_site ||= Site[id: session[:id]]
end

def parent_site
  return nil if current_site.nil?
  current_site.parent? ? current_site : current_site.parent
end

def require_unbanned_ip
  if session[:banned] || Site.banned_ip?(request.ip)
    session[:id] = nil
    session[:banned] = true
    flash[:error] = 'Site creation has been banned due to ToS violation/spam. '+
    'If you believe this to be in error, <a href="/contact">contact the site admin</a>.'
    return {result: 'error'}.to_json
  end
end

def title
  out = "Neocities"
  return out                  if request.path == '/'
  return "#{out} - #{@title}" if @title
  "#{out} - #{request.path.gsub('/', '').capitalize}"
end

def encoding_fix(file)
  begin
    Rack::Utils.escape_html file
  rescue ArgumentError => e
    return Rack::Utils.escape_html(file.force_encoding('BINARY')) if e.message =~ /invalid byte sequence in UTF-8/
    fail
  end
end

def require_api_credentials
  if !request.env['HTTP_AUTHORIZATION'].nil?
    init_api_credentials
  else
    api_error_invalid_auth
  end
end

def init_api_credentials
  auth = request.env['HTTP_AUTHORIZATION']

  begin
    user, pass = Base64.decode64(auth.match(/Basic (.+)/)[1]).split(':')
  rescue
    api_error_invalid_auth
  end

  if Site.valid_login? user, pass
    site = Site[username: user]

    if site.nil? || site.is_banned
      api_error_invalid_auth
    end

    session[:id] = site.id
  else
    api_error_invalid_auth
  end
end

def api_success(message_or_obj)
  output = {result: 'success'}

  if message_or_obj.is_a?(String)
    output[:message] = message_or_obj
  else
    output.merge! message_or_obj
  end

  api_response(200, output)
end

def api_response(status, output)
  halt status, JSON.pretty_generate(output)+"\n"
end

def api_error(status, error_type, message)
  api_response(status, result: 'error', error_type: error_type, message: message)
end

def api_error_invalid_auth
  api_error 403, 'invalid_auth', 'invalid credentials - please check your username and password'
end

def api_not_found
  api_error 404, 'not_found', 'the requested api call does not exist'
end

def send_confirmation_email(site=current_site)
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'contact@neocities.org',
    to: site.email,
    subject: "[Neocities] Confirm your email address",
    body: Tilt.new('./views/templates/email_confirm.erb', pretty: true).render(self, site: site)
  })
end