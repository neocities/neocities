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
  return false if current_site.nil?
  true
end

def signout
  @_site = nil
  @_parent_site = nil
  session[:id] = nil
  session.clear
  response.delete_cookie 'neocities', path: '/'
  request.env['rack.session.options'][:drop] = true
end

def current_site
  return nil if session[:id].nil?
  @_site ||= Site[id: session[:id]]
  @_parent_site ||= @_site.parent

  if @_site.is_banned || @_site.is_deleted || (@_parent_site && (@_parent_site.is_banned || @_parent_site.is_deleted))
    signout
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
  return out if request.path == '/'
  
  full_title = if @title
    "#{out} - #{Rack::Utils.escape_html(@title)}"
  else
    path_parts = request.path.split('/').reject(&:empty?)
    formatted_parts = path_parts.map do |part|
      escaped_part = Rack::Utils.escape_html(part)
      escaped_part.split(/[_\-]/).map(&:capitalize).join(' ')
    end
    "#{out} - #{formatted_parts.join(' - ')}"
  end
  
  if full_title.length >= 70
    full_title[0..65] + "..."
  else
    full_title
  end
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
  # Child sites don't need email confirmation - they use parent site's email
  return if !site.parent?

  if site.email_confirmation_count > Site::MAXIMUM_EMAIL_CONFIRMATIONS
    flash[:error] = 'You sent too many email confirmation requests, cannot continue.'
    redirect request.referrer
  end

  DB['UPDATE sites set email_confirmation_count=email_confirmation_count+1 WHERE id=?', site.id].first

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'noreply@neocities.org',
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

def sanitize_comment(text)
  Rinku.auto_link Sanitize.fragment(text), :all, 'target="_blank" rel="nofollow"'
end

def flash_display(opts={})
  erb :'_flash', layout: false, locals: {opts: opts}
end

def hcaptcha_valid?
  return true if ENV['RACK_ENV'] == 'test' || ENV['CI']
  return false unless params[:'h-captcha-response']

  resp = HTTP.get('https://hcaptcha.com/siteverify', params: {
    secret: $config['hcaptcha_secret_key'],
    response: params[:'h-captcha-response']
  })

  resp = JSON.parse resp

  if resp['success'] == true
    true
  else
    false
  end
end

JS_ESCAPE_MAP = {"\\" => "\\\\", "</" => '<\/', "\r\n" => '\n', "\n" => '\n', "\r" => '\n', '"' => '\\"', "'" => "\\'", "`" => "\\`", "$" => "\\$"}

def escape_javascript(javascript)
  javascript = javascript.to_s
  if javascript.empty?
    result = ""
  else
    result = javascript.gsub(/(\\|<\/|\r\n|\342\200\250|\342\200\251|[\n\r"']|[`]|[$])/u, JS_ESCAPE_MAP)
  end
  result
end
