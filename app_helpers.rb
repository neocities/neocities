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

EMAIL_LOGIN_CODE_TTL = 10.minutes.to_i
EMAIL_LOGIN_MAX_ATTEMPTS = 5
EMAIL_LOGIN_ACCOUNT_LIMIT = 1
EMAIL_LOGIN_IP_LIMIT = 60
EMAIL_LOGIN_RATE_LIMIT_WINDOW = 1.minute.to_i

def email_login_digest(value)
  secret = Base64.strict_decode64($config['session_secret'])
  OpenSSL::HMAC.hexdigest('SHA256', secret, value)
end

def email_login_challenge_key(challenge_id)
  "email_login:challenge:#{challenge_id}"
end

def email_login_attempts_key(challenge_id)
  "email_login:attempts:#{challenge_id}"
end

def email_login_owner_key(owner_id)
  "email_login:owner:#{owner_id}"
end

def email_login_account_digest(site)
  owner = site.owner
  email_login_digest [owner.id, owner.values[:password], owner.email].join("\0")
end

def clear_pending_email_login(delete_challenge: true)
  challenge_id = session.delete(:email_login_challenge_id)
  return if challenge_id.nil?

  if delete_challenge
    $redis_cache.del email_login_challenge_key(challenge_id)
    $redis_cache.del email_login_attempts_key(challenge_id)
  end
end

def invalidate_email_login_challenges(site)
  owner = site.owner
  owner_key = email_login_owner_key owner.id
  challenge_id = $redis_cache.get owner_key
  return if challenge_id.nil?

  $redis_cache.del owner_key
  $redis_cache.del email_login_challenge_key(challenge_id)
  $redis_cache.del email_login_attempts_key(challenge_id)
end

def email_login_rate_limit_key(type, value)
  window = Time.now.to_i/EMAIL_LOGIN_RATE_LIMIT_WINDOW
  "email_login:rate:#{type}:#{value}:#{window}"
end

def email_login_under_rate_limit?(type, value, limit)
  key = email_login_rate_limit_key type, value
  count = $redis_cache.incr key
  $redis_cache.expire key, EMAIL_LOGIN_RATE_LIMIT_WINDOW*2
  count <= limit
end

def email_login_issuance_allowed?(site, ip)
  return false unless email_login_under_rate_limit? :owner, site.owner.id, EMAIL_LOGIN_ACCOUNT_LIMIT

  email_login_under_rate_limit? :ip, ip, EMAIL_LOGIN_IP_LIMIT
end

def pending_email_login
  challenge_id = session[:email_login_challenge_id]
  return nil if challenge_id.nil?

  raw_challenge = $redis_cache.get email_login_challenge_key(challenge_id)
  return nil if raw_challenge.nil?

  challenge = JSON.parse raw_challenge
  site = Site[id: challenge['site_id']]
  return nil if site.nil? || site.is_banned || site.owner.is_banned

  restore = challenge['action'] == 'restore'
  return nil if site.is_deleted && !restore
  return nil if site.owner.is_deleted && !(restore && site.owner.id == site.id)
  return nil unless $redis_cache.get(email_login_owner_key(site.owner.id)) == challenge_id

  current_account_digest = email_login_account_digest site
  return nil unless Rack::Utils.secure_compare(current_account_digest, challenge['account_digest'].to_s)

  {id: challenge_id, site: site, code_digest: challenge['code_digest'], action: challenge['action']}
rescue JSON::ParserError
  nil
end

def consume_email_login_challenge(challenge)
  deleted = $redis_cache.del email_login_challenge_key(challenge[:id])
  return false unless deleted == 1

  clear_pending_email_login delete_challenge: false
  true
end

def record_failed_email_login_attempt(challenge)
  attempts = $redis_cache.incr email_login_attempts_key(challenge[:id])

  if attempts >= EMAIL_LOGIN_MAX_ATTEMPTS
    $redis_cache.del email_login_challenge_key(challenge[:id])
    clear_pending_email_login delete_challenge: false
  end

  attempts
end

def begin_email_login(site, ip, action: nil)
  return false unless email_login_issuance_allowed? site, ip

  invalidate_email_login_challenges site

  challenge_id = SecureRandom.hex 32
  code = SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')
  challenge = {
    site_id: site.id,
    code_digest: email_login_digest(code),
    account_digest: email_login_account_digest(site),
    action: action
  }

  $redis_cache.set email_login_attempts_key(challenge_id), 0, ex: EMAIL_LOGIN_CODE_TTL
  $redis_cache.set email_login_challenge_key(challenge_id), challenge.to_json, ex: EMAIL_LOGIN_CODE_TTL
  $redis_cache.set email_login_owner_key(site.owner.id), challenge_id, ex: EMAIL_LOGIN_CODE_TTL

  begin
    EmailWorker.perform_async({
      from: Site::FROM_EMAIL,
      to: site.owner.email,
      subject: '[Neocities] Your sign in verification code',
      body: Tilt.new('./views/templates/email/signin_code.erb', pretty: true).render(self, code: code),
      no_footer: true
    })
  rescue StandardError
    invalidate_email_login_challenges site
    raise
  end

  session[:email_login_challenge_id] = challenge_id
  true
end

def masked_email(email)
  local, domain = email.to_s.split('@', 2)
  return '' if local.nil? || domain.nil?

  visible = local[0, [local.length, 2].min]
  "#{visible}#{'*' * [local.length-visible.length, 3].max}@#{domain}"
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

def meta_description(new_description=nil)
  if new_description
    @_meta_description = new_description
  end

  description = @_meta_description || @description
  return nil if description.nil? || description.strip.empty?

  description
end

def title
  out = "Neocities"
  return out if request.path == '/'
  
  full_title = if @title
    "#{out} - #{@title}"
  else
    path_parts = request.path.split('/').reject(&:empty?)
    formatted_parts = path_parts.map do |part|
      part.split(/[_\-]/).map(&:capitalize).join(' ')
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

def flash_message_keys
  flash.keys.select {|k| [:success, :error, :errors].include?(k) && !flash[k].to_s.empty?}
end

def flash_message_entries
  entries = []

  Array(@error).each do |message|
    entries << {type: 'error', message: message} unless message.to_s.empty?
  end

  flash_message_keys.each do |key|
    type = key == :success ? 'success' : 'error'

    Array(flash[key]).each do |message|
      entries << {type: type, message: message} unless message.to_s.empty?
    end
  end

  entries
end

def normalize_comment_message(message)
  message.to_s.gsub(/\r\n?/, "\n").gsub(/\n{3,}/, "\n\n").strip
end

def comment_message_error(message)
  return 'Comment cannot be empty.' if message.empty?
  return "Comments must be #{Site::MAX_COMMENT_SIZE} characters or fewer." if message.length > Site::MAX_COMMENT_SIZE

  lines = message.split("\n")
  return "Comments must be #{Site::MAX_COMMENT_LINES} lines or fewer." if lines.length > Site::MAX_COMMENT_LINES

  return nil if lines.length < Site::MULTILINE_COMMENT_AVERAGE_LINE_THRESHOLD

  nonblank_lines = lines.map(&:strip).reject(&:empty?)
  return 'Comment cannot be empty.' if nonblank_lines.empty?

  average_line_length = nonblank_lines.sum(&:length).to_f / nonblank_lines.length
  return nil if average_line_length >= Site::MIN_MULTILINE_COMMENT_AVERAGE_LINE_LENGTH

  'Multiline comments need a little more text on each line.'
end

def valid_comment_message?(message)
  comment_message_error(message).nil?
end

def comment_unavailable_message(site=nil)
  return 'Comments are disabled for this site.' if site && site.profile_comments_enabled == false

  if current_site && !current_site.commenting_allowed?
    if current_site.commenting_too_much?
      return "To prevent spam, comments are limited to #{Site::MAX_COMMENTS_PER_DAY} per day. Please try again tomorrow."
    end

    return "To prevent spam, you cannot comment until you have updated your site #{Site::COMMENTING_ALLOWED_UPDATED_COUNT} times on separate days, and your account is one week old."
  end

  'You cannot comment on this right now.'
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
