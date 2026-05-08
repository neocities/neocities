# frozen_string_literal: true

require_relative './environment.rb'
require 'rack/test'

module PayPalRecurringTestHelpers
  def configure_test_paypal
    @paypal_config = {
      sandbox: PayPalRecurring.sandbox,
      username: PayPalRecurring.username,
      password: PayPalRecurring.password,
      signature: PayPalRecurring.signature
    }

    PayPalRecurring.configure do |config|
      config.sandbox = false
      config.username = 'api-user'
      config.password = 'api-pass'
      config.signature = 'api-signature'
    end
  end

  def restore_paypal_config
    PayPalRecurring.configure do |config|
      config.sandbox = @paypal_config[:sandbox]
      config.username = @paypal_config[:username]
      config.password = @paypal_config[:password]
      config.signature = @paypal_config[:signature]
    end
  end

  def stub_paypal_response(expected_params, body)
    stub_request(:post, PayPalRecurring.api_endpoint).with do |request|
      params = URI.decode_www_form(request.body).to_h
      expected_params.all? { |name, value| params[name] == value }
    end.to_return(status: 200, body: body)
  end

  def recurring_params
    {
      ipn_url:     'https://neocities.org/webhooks/paypal',
      description: 'Neocities Supporter - Monthly',
      amount:      '5.0',
      currency:    'USD'
    }
  end

  def authorization_params
    recurring_params.merge(
      return_url: 'https://neocities.org/supporter/paypal/return',
      cancel_url: 'https://neocities.org/supporter'
    )
  end
end

describe PayPalRecurring do
  include PayPalRecurringTestHelpers

  before do
    configure_test_paypal
  end

  after do
    restore_paypal_config
  end

  it 'starts an express checkout recurring billing agreement' do
    stub_paypal_response({
      'METHOD' => 'SetExpressCheckout',
      'USER' => 'api-user',
      'PWD' => 'api-pass',
      'SIGNATURE' => 'api-signature',
      'VERSION' => PayPalRecurring::API_VERSION,
      'PAYMENTREQUEST_0_AMT' => '5.0',
      'AMT' => '5.0',
      'PAYMENTREQUEST_0_CURRENCYCODE' => 'USD',
      'CURRENCYCODE' => 'USD',
      'DESC' => 'Neocities Supporter - Monthly',
      'L_BILLINGAGREEMENTDESCRIPTION0' => 'Neocities Supporter - Monthly',
      'PAYMENTREQUEST_0_NOTIFYURL' => 'https://neocities.org/webhooks/paypal',
      'NOTIFYURL' => 'https://neocities.org/webhooks/paypal',
      'RETURNURL' => 'https://neocities.org/supporter/paypal/return',
      'CANCELURL' => 'https://neocities.org/supporter',
      'PAYMENTREQUEST_0_PAYMENTACTION' => 'Authorization',
      'NOSHIPPING' => '1',
      'L_BILLINGTYPE0' => 'RecurringPayments'
    }, 'ACK=Success&TOKEN=EC-123')

    response = PayPalRecurring.new(authorization_params).checkout

    _(response.valid?).must_equal true
    _(response.token).must_equal 'EC-123'
    _(response.checkout_url).must_equal 'https://www.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=EC-123&useraction=commit'
  end

  it 'requests the initial payment after PayPal redirects back' do
    stub_paypal_response({
      'METHOD' => 'DoExpressCheckoutPayment',
      'PAYMENTREQUEST_0_PAYMENTACTION' => 'Sale',
      'TOKEN' => 'EC-123',
      'PAYERID' => 'PAYER-123',
      'PAYMENTREQUEST_0_AMT' => '5.0',
      'AMT' => '5.0'
    }, 'ACK=Success&PAYMENTINFO_0_ACK=Success&PAYMENTINFO_0_PAYMENTSTATUS=Completed')

    response = PayPalRecurring.new(recurring_params.merge(
      token: 'EC-123',
      payer_id: 'PAYER-123'
    )).request_payment

    _(response.approved?).must_equal true
    _(response.completed?).must_equal true
  end

  it 'creates the recurring payments profile' do
    stub_paypal_response({
      'METHOD' => 'CreateRecurringPaymentsProfile',
      'TOKEN' => 'EC-123',
      'PAYERID' => 'PAYER-123',
      'PROFILEREFERENCE' => '42',
      'PROFILESTARTDATE' => '2026-01-02T03:04:05Z',
      'MAXFAILEDPAYMENTS' => '3',
      'AUTOBILLOUTAMT' => 'AddToNextBilling',
      'BILLINGFREQUENCY' => '1',
      'BILLINGPERIOD' => 'Month'
    }, 'ACK=Success&PROFILEID=I-123&PROFILESTATUS=ActiveProfile')

    response = PayPalRecurring.new(authorization_params.merge(
      frequency: 1,
      token: 'EC-123',
      period: :monthly,
      reference: '42',
      payer_id: 'PAYER-123',
      start_at: Time.utc(2026, 1, 2, 3, 4, 5),
      failed: 3,
      outstanding: :next_billing
    )).create_recurring_profile

    _(response.valid?).must_equal true
    _(response.profile_id).must_equal 'I-123'
  end

  it 'cancels a recurring payments profile' do
    stub_paypal_response({
      'METHOD' => 'ManageRecurringPaymentsProfileStatus',
      'ACTION' => 'Cancel',
      'PROFILEID' => 'I-123'
    }, 'ACK=Success&PROFILEID=I-123&PROFILESTATUS=Cancelled')

    response = PayPalRecurring.new(profile_id: 'I-123').cancel

    _(response.valid?).must_equal true
    _(response.profile_id).must_equal 'I-123'
  end

  it 'collects PayPal NVP errors' do
    stub_paypal_response({
      'METHOD' => 'SetExpressCheckout'
    }, 'ACK=Failure&L_ERRORCODE0=10001&L_SHORTMESSAGE0=Internal%20Error&L_LONGMESSAGE0=Try%20again')

    response = PayPalRecurring.new(authorization_params).checkout

    _(response.valid?).must_equal false
    _(response.errors).must_equal [{
      code: '10001',
      messages: ['Internal Error', 'Try again']
    }]
  end

  it 'uses peer verification with the system certificate store' do
    client = PayPalRecurring.new.send(:http_client, URI(PayPalRecurring.api_endpoint))

    _(client.use_ssl?).must_equal true
    _(client.verify_mode).must_equal OpenSSL::SSL::VERIFY_PEER
    _(client.ca_file).must_be_nil
    _(client.cert_store).must_be_instance_of OpenSSL::X509::Store
  end

  it 'sets explicit network timeouts' do
    client = PayPalRecurring.new.send(:http_client, URI(PayPalRecurring.api_endpoint))

    _(client.open_timeout).must_equal PayPalRecurring::OPEN_TIMEOUT
    _(client.read_timeout).must_equal PayPalRecurring::READ_TIMEOUT
    _(client.write_timeout).must_equal PayPalRecurring::WRITE_TIMEOUT
  end

  it 'returns an invalid response for network errors' do
    stub_request(:post, PayPalRecurring.api_endpoint).to_timeout

    response = PayPalRecurring.new(profile_id: 'I-123').cancel

    _(response.valid?).must_equal false
    _(response.network_error?).must_equal true
    _(response.errors.first[:code]).must_equal 'network_error'
  end
end

describe 'PayPal supporter routes' do
  include Rack::Test::Methods
  include PayPalRecurringTestHelpers

  def app
    Sinatra::Application
  end

  before do
    configure_test_paypal
    @site = Fabricate :site
  end

  after do
    restore_paypal_config
  end

  it 'does not upgrade the site when recurring profile creation fails' do
    stub_paypal_response({
      'METHOD' => 'DoExpressCheckoutPayment',
      'TOKEN' => 'EC-123',
      'PAYERID' => 'PAYER-123'
    }, 'ACK=Success&PAYMENTINFO_0_ACK=Success&PAYMENTINFO_0_PAYMENTSTATUS=Completed')
    stub_paypal_response({
      'METHOD' => 'CreateRecurringPaymentsProfile',
      'TOKEN' => 'EC-123',
      'PAYERID' => 'PAYER-123'
    }, 'ACK=Failure&L_ERRORCODE0=10001&L_SHORTMESSAGE0=Internal%20Error')

    get '/supporter/paypal/return',
      {token: 'EC-123', PayerID: 'PAYER-123'},
      {'rack.session' => {'id' => @site.id}}

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_equal 'http://example.org/supporter'
    @site.reload
    _(@site.values[:paypal_active]).wont_equal true
    _(@site.paypal_profile_id).must_be_nil
    _(@site.plan_type).must_equal 'free'
  end

  it 'does not clear local PayPal membership when cancellation fails' do
    @site.update(
      paypal_active: true,
      paypal_profile_id: 'I-123',
      paypal_token: 'EC-123',
      plan_type: 'supporter',
      plan_ended: false
    )
    stub_paypal_response({
      'METHOD' => 'ManageRecurringPaymentsProfileStatus',
      'ACTION' => 'Cancel',
      'PROFILEID' => 'I-123'
    }, 'ACK=Failure&L_ERRORCODE0=10001&L_SHORTMESSAGE0=Internal%20Error')

    post '/supporter/end',
      {csrf_token: 'abcd'},
      {'rack.session' => {'id' => @site.id, '_csrf_token' => 'abcd'}}

    _(last_response.status).must_equal 302
    _(last_response.headers['Location']).must_equal 'http://example.org/settings'
    @site.reload
    _(@site.paypal_active).must_equal true
    _(@site.paypal_profile_id).must_equal 'I-123'
    _(@site.paypal_token).must_equal 'EC-123'
    _(@site.plan_type).must_equal 'supporter'
    _(@site.plan_ended).must_equal false
  end
end
