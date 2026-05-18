# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe 'tipping' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    EmailWorker.jobs.clear
    @site = Fabricate :site
  end

  it 'adds a tip' do
    @actioning_site = Fabricate :site
    custom = Base64.strict_encode64({site_id: @site.id, actioning_site_id: (@actioning_site ? @actioning_site.id : nil)}.to_json)

    paypal_hash = paypal_tip_webhook_hash(
      site: @site,
      actioning_site: @actioning_site,
      custom: custom,
      memo: 'I like your site',
      payer_email: @actioning_site.email,
      receiver_email: @site.email
    )

    post '/webhooks/paypal/tipping_notify', paypal_hash

    _(@site.tips.length).must_equal 1
    tip = @site.tips.first
    _(tip.site.id).must_equal @site.id
    _(tip.actioning_site.id).must_equal @actioning_site.id
    _(tip.currency).must_equal 'USD'
    _(tip.amount_string).must_equal '$5.00'
    _(tip.fee_string).must_equal '$0.45'
    _(tip.message).must_equal 'I like your site'
    _(tip.paypal_payer_email).must_equal @actioning_site.email
    _(tip.paypal_receiver_email).must_equal @site.email
    _(tip.paypal_txn_id).must_equal 'TXID'
    _(tip.created_at).must_equal Time.parse("2017-02-03 21:39:51 -0800")

    _(EmailWorker.jobs.length).must_equal 2
  end

  it 'adds a tip even if there is no actioning site id' do
    @actioning_site = Fabricate :site
    custom = Base64.strict_encode64({site_id: @site.id, actioning_site_id: nil}.to_json)

    payer_email = 'notloggedintipper@dfdsfdsfdsfdsfsdf.com'

    paypal_hash = paypal_tip_webhook_hash(
      site: @site,
      custom: custom,
      memo: 'I like your site',
      payer_email: payer_email,
      receiver_email: @site.email
    )

    post '/webhooks/paypal/tipping_notify', paypal_hash

    _(@site.tips.length).must_equal 1
    _(@site.tips.first.actioning_site_id).must_be_nil
  end
end

describe 'paypal supporter IPN' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    EmailWorker.jobs.clear
    @site = Fabricate :site
    @site.update(
      paypal_active: true,
      paypal_profile_id: 'I-123',
      paypal_token: 'EC-123',
      plan_type: 'supporter',
      plan_ended: false
    )
  end

  it 'ends a PayPal supporter membership when PayPal cancels the recurring profile' do
    post '/webhooks/paypal', paypal_supporter_ipn_hash

    _(last_response.status).must_equal 200
    @site.reload
    _(@site.values[:paypal_active]).must_equal false
    _(@site.paypal_profile_id).must_be_nil
    _(@site.paypal_token).must_be_nil
    _(@site.values[:plan_type]).must_be_nil
    _(@site.plan_ended).must_equal true

    _(EmailWorker.jobs.length).must_equal 1
    args = EmailWorker.jobs.first['args'].first
    _(args['to']).must_equal @site.email
    _(args['subject']).must_equal '[Neocities] Supporter plan has ended'
  end

  it 'clears stale PayPal fields without ending an active Stripe membership' do
    @site.update(
      stripe_customer_id: 'cus_123',
      stripe_subscription_id: 'sub_123',
      plan_type: 'supporter',
      plan_ended: false
    )

    post '/webhooks/paypal', paypal_supporter_ipn_hash

    _(last_response.status).must_equal 200
    @site.reload
    _(@site.values[:paypal_active]).must_equal false
    _(@site.paypal_profile_id).must_be_nil
    _(@site.paypal_token).must_be_nil
    _(@site.values[:plan_type]).must_equal 'supporter'
    _(@site.plan_ended).must_equal false
    _(EmailWorker.jobs.length).must_equal 0
  end
end

def paypal_supporter_ipn_hash(opts={})
  {
    txn_type: 'recurring_payment_profile_cancel',
    recurring_payment_id: 'I-123'
  }.merge(opts)
end

def paypal_tip_webhook_hash(opts={})
  {
    :transaction_subject=>"customvarlol",
    :payment_date=>"21:39:51 Feb 03, 2017 PST",
    :txn_type=>"web_accept",
    :last_name=>"Drake",
    :residence_country=>"US",
    :item_name=>"Site Donation for JUICED UP TEST MACHINE!!!",
    :payment_gross=>"5.00",
    :mc_currency=>"USD",
    :business=>"admin@neocities.org",
    :payment_type=>"instant",
    :protection_eligibility=>"Ineligible",
    :verify_sign=>"AQEgFLG-gYJRPNwVRAb4gD.Dx6t9AmFm1mbPa6iYv5jJAKHYWjLwCX9z",
    :payer_status=>"verified",
    :payer_email=>"kyle@kyledrake.net",
    :txn_id=>"TXID",
    :quantity=>"0",
    :receiver_email=>"admin@neocities.org",
    :first_name=>"Kyle",
    :payer_id=>"PAYERID",
    :receiver_id=>"RECEIVERID",
    :item_number=>"",
    :payment_status=>"Completed",
    :payment_fee=>"0.45",
    :mc_fee=>"0.45",
    :mc_gross=>"5.00",
    :custom=>"",
    :charset=>"windows-1252",
    :notify_version=>"3.8",
    :ipn_track_id=>"IPNTRACKID"
  }.merge(opts)
end
