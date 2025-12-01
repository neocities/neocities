get '/contact' do
  @show_contact_form = params[:show_contact_form] == 'yes'
  erb :'contact'
end

post '/contact' do
  @errors = []
  if params[:email].empty? || params[:subject].empty? || params[:body].empty?
    @errors << 'Please fill out all fields'
  end

  if params[:email] != params[:confirm_email]
    @errors << 'Email addresses do not match'
  end

  if params[:faq_check] == 'no'
    @errors << 'Please check Frequently Asked Questions before sending a contact message'
  end

  unless hcaptcha_valid?
    @errors << 'Captcha was not filled out (or was filled out incorrectly)'
  end

  if !@errors.empty?
    erb :'contact'
  else
    body = params[:body]

    if current_site
      body = "current username: #{current_site.username}\n\n" + body
      if parent_site != current_site
        body = "parent username: #{parent_site.username}\n\n" + body
      end
    end

    if current_site && current_site.supporter?
      subject = "[Neocities Supporter Contact]: #{params[:subject]}"
    else
      subject = "[Neocities Contact]: #{params[:subject]}"
    end

    EmailWorker.perform_async({
      from: Site::FROM_EMAIL,
      reply_to: params[:email],
      to: $config['support_email'],
      subject: subject,
      body: body,
      no_footer: true
    })

    flash[:success] = 'Your contact message has been sent.'
    redirect '/'
  end
end
