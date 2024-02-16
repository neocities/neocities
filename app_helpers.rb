def dashboard_if_signed_in
  redirect '/dashboard' if signed_in?
end

def csrf_safe?
  csrf_token == params[:csrf_token] || csrf_token == request.env['HTTP_X_CSRF_TOKEN']
end

def csrf_token
   session[:_csrf_token] ||= SecureRandom.base64(32)
end

def is_education?
  current_site && current_site.is_education
end

def require_login
  redirect '/' unless signed_in? && current_site
end

def signed_in?
  !session[:id].nil?
end

def current_site
  return nil if session[:id].nil?
  @_site ||= Site[id: session[:id]]
  @_parent_site ||= @_site.parent

  if @_site.is_banned || @_site.is_deleted || (@_parent_site && (@_parent_site.is_banned || @_parent_site.is_deleted))
    signout
    redirect '/'
  end

  @_site
end

def parent_site
  @_parent_site || current_site
end

def meta_robots(newtag=nil)
  if newtag
    @_meta_robots = newtag
  end

  @_meta_robots
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
    if e.message =~ /invalid byte sequence in UTF-8/ ||
       e.message =~ /incompatible character encodings/
      return Rack::Utils.escape_html(file.force_encoding('BINARY'))
    end
    fail
  end
end

def send_confirmation_email(site=current_site)
  if site.email_confirmation_count > Site::MAXIMUM_EMAIL_CONFIRMATIONS
    flash[:error] = 'You sent too many email confirmation requests, cannot continue.'
    redirect request.referrer
  end

  DB['UPDATE sites set email_confirmation_count=email_confirmation_count+1 WHERE id=?', site.id].first

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'contact@neocities.org',
    to: site.email,
    subject: "[Neocities] Confirm your email address",
    body: Tilt.new('./views/templates/email/confirm.erb', pretty: true).render(self, site: site)
  })
end

def dont_browser_cache
  headers['Cache-Control'] = 'private, no-store, max-age=0, no-cache, must-revalidate, post-check=0, pre-check=0'
  headers['Pragma'] = 'no-cache'
  headers['Expires'] = 'Fri, 01 Jan 1990 00:00:00 GMT'
  @dont_browser_cache = true
end

def email_not_validated?
  return false if current_site && current_site.created_at < Site::EMAIL_VALIDATION_CUTOFF_DATE

  current_site && current_site.parent? && !current_site.is_education && !current_site.email_confirmed && !current_site.supporter?
end

def sanitize_comment(text)
  Rinku.auto_link Sanitize.fragment(text), :all, 'target="_blank" rel="nofollow"'
end

def flash_display(opts={})
  erb :'_flash', layout: false, locals: {opts: opts}
end

def hcaptcha_valid?
  return true if ENV['RACK_ENV'] == 'test' || ENV['CI']
  return false unless params[:'h-captcha-response']

  resp = Net::HTTP.get URI(
    'https://hcaptcha.com/siteverify?'+
    Rack::Utils.build_query(
      secret: $config['hcaptcha_secret_key'],
      response: params[:'h-captcha-response']
    )
  )

  resp = JSON.parse resp

  if resp['success'] == true
    true
  else
    false
  end
end
