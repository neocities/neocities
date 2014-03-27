require_relative './environment'

include Rack::Test::Methods

def app;     App end
def status;  last_response.status end
def headers; last_response.headers end
def body;    last_response.body end

describe 'index' do
  it 'loads' do
    get '/'
    status.must_equal 200
  end
end

describe 'signin' do
  it 'fails for missing login' do
    post '/signin', username: 'derpie', password: 'lol'
    fail_signin
  end

  it 'fails for bad password' do
    @site = Fabricate :site
    post '/signin', username: @site.username, password: 'derp'
    fail_signin
  end

  it 'fails for no input' do
    post '/signin'
    fail_signin
  end

  it 'succeeds for valid input' do
    password = '1tw0rkz'
    @account = Fabricate :account, password: password
    post '/accounts/signin', username: @account.email, password: password
    headers['Location'].must_equal 'http://example.org/dashboard'
    mock_dashboard_calls @account.email
    get '/dashboard'
    body.must_match /Dashboard/
  end
end

describe 'account creation' do
  it 'fails for no input' do
    post '/accounts/create'
    status.must_equal 200
    body.must_match /There were some errors.+Valid email address is required.+Password must be/
  end

  it 'fails with invalid email' do
    post '/accounts/create', email: 'derplol'
    status.must_equal 200
    body.must_match /errors.+valid email/i
  end

  it 'fails with invalid password' do
    post '/accounts/create', 'email@example.com', password: 'sdd'
    status.must_equal 200
    body.must_match /errors.+Password must be at least #{Account::MINIMUM_PASSWORD_LENGTH} characters/i
  end

  it 'succeeds with valid info' do
    account_attributes = Fabricate.attributes_for :account

    mock_dashboard_calls account_attributes[:email]

    post '/accounts/create', account_attributes
    status.must_equal 302
    headers['Location'].must_equal 'http://example.org/dashboard'
    
    get '/dashboard'
    body.must_match /Dashboard/
  end
end

describe 'temporary account login' do
end

def fail_signin
  headers['Location'].must_equal 'http://example.org/'
  get '/'
  body.must_match /invalid signin/i
end

def api_url
  uri = Addressable::URI.parse $config['bitcoind_rpchost'] ? $config['bitcoind_rpchost'] : 'http://localhost'
  uri.port = 8332 if uri.port.nil?
  uri.user = $config['bitcoind_rpcuser'] if uri.user.nil?
  uri.password = $config['bitcoind_rpcpassword'] if uri.password.nil?
  "#{uri.to_s}/"
end