def kickstarter_days_remaining
  ending = Time.parse('Sat, Jul 25 2015 3:05 PM PDT')
  today = Time.now

  remaining = ending - today
  return 0 if remaining < 0

  ((ending - today) / 86400).to_i
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

def is_education?
  current_site && current_site.is_education
end

def require_login
  redirect '/' unless signed_in?
  if session[:banned] || current_site.is_banned || parent_site.is_banned
    signout
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
  if session[:banned] || (is_banned_ip = Site.banned_ip?(request.ip))
    signout
    session[:banned] = request.ip if !session[:banned]

    flash[:error] = 'Site creation has been banned due to a Terms of Service violation from your location. '+
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
    if e.message =~ /invalid byte sequence in UTF-8/ ||
       e.message =~ /incompatible character encodings/
      return Rack::Utils.escape_html(file.force_encoding('BINARY'))
    end
    fail
  end
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

def plan_pricing_button(plan_type)
  plan_type = plan_type.to_s

  if !parent_site
    %{<a href="/#new" class="btn-Action">Sign Up</a>}
  elsif parent_site && parent_site.plan_type == plan_type
    if request.path.match /\/welcome/
      %{<a href="/" class="btn-Action">Get Started</a>}
    else
      %{<div class="current-plan">Current Plan</div>}
    end
  else
    #if plan_type == 'supporter'
    #  plan_price = "$#{Site::PLAN_FEATURES[plan_type.to_sym][:price]*12}, once per year"
    #else
      plan_price = "$#{Site::PLAN_FEATURES[plan_type.to_sym][:price]}, monthly"
    #end

    if request.path.match /\/welcome/
      button_title = 'Get Started'
    else
      button_title = parent_site.plan_type == 'free' ? 'Upgrade' : 'Change'
    end

    %{<a data-plan_name="#{Site::PLAN_FEATURES[plan_type.to_sym][:name]}" data-plan_type="#{plan_type}" data-plan_price="#{plan_price}" onclick="card = new Skeuocard($('#skeuocard')); return false" class="btn-Action planPricingButton">#{button_title}</a>}
  end
end
