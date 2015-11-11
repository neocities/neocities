get '/dmca' do
  erb :'dmca'
end

get '/dmca/contact_info' do
  content_type :json
  {data: erb(:'dmca/contact_info', layout: false)}.to_json
end

post '/dmca/contact' do
  @errors = []

  if params[:email].empty? || params[:subject].empty? || params[:urls].empty? || params[:body].empty?
    @errors << 'Please fill out all fields'
  end

  if !recaptcha_valid?
    @errors << 'Captcha was not filled out (or was filled out incorrectly)'
  end

  if !@errors.empty?
    erb :'dmca'
  else
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      reply_to: params[:email],
      to: 'dmca@neocities.org',
      subject: "[Neocities DMCA Notice]: #{params[:subject]}",
      body: "#{params[:urls].to_s}\n#{params[:body].to_s}",
      no_footer: true
    })

    flash[:success] = 'Your DMCA notification has been sent.'
    redirect '/'
  end
end
