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
      body: params[:body],
      no_footer: true
    })

    flash[:success] = 'Your contact has been sent.'
    redirect '/'
  end
end
