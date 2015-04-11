require './environment.rb'
require './app_helpers.rb'

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

set :protection, :frame_options => "ALLOW-FROM #{$config['surf_iframe_source']}"

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/webhooks\//
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
    body: erb(:'views/templates/email/error'),
    no_footer: true
  })

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

Dir['./app/**/*.rb'].each {|f| require f}
