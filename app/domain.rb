get '/domain/new' do
  require_login
  @title = 'Register a Domain'

  erb :'domain/new'
end

post '/domain/check_availability.json' do
  require_login
  content_type :json

  timer = Time.now.to_i

  while true
    if (Time.now.to_i - timer) > 60
      api_error 200, :contact_fail, 'Error contacting domain server, please try again.'
    end

    begin
      res = $gandi.domain.available([params[:domain]])[params[:domain]]
    rescue => Gandi::DataError
      api_error 200, :invalid_domain, 'Domain name was invalid, please try another.'
    end

    api_success res unless res == 'pending'
    sleep 0.2
  end

end
