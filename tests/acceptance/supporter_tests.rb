require_relative './environment.rb'

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, js_errors: false)
end

describe '/supporter' do
  include Capybara::DSL

  before do
    Capybara.default_driver = :poltergeist
    Capybara.reset_sessions!

    @site = Fabricate :site
    @stripe_helper = StripeMock.create_test_helper
    StripeMock.start
    @stripe_helper.create_plan id: 'special', amount: 0
    @stripe_helper.create_plan id: 'supporter', amount: 500
    @stripe_helper.create_plan id: 'free', amount: 0
    page.set_rack_session id: @site.id
    EmailWorker.jobs.clear
    Mail::TestMailer.deliveries.clear
  end

  after do
    StripeMock.stop
    Capybara.default_driver = :rack_test
  end

  it 'should work for paypal' do

  end

  it 'should work for fresh signup' do
    visit '/supporter'
    find('#cc_number', visible: false).set '4242424242424242'
    find('#cc_exp_month', visible: false).set '01'
    find('#cc_exp_year', visible: false).set Date.today.next_year.year.to_s[2..3]
    find('#cc_name', visible: false).set 'Penelope'
    find('#cc_cvc', visible: false).set '123'
    find('#stripe_token', visible: false).set @stripe_helper.generate_card_token
    click_link 'Upgrade for $5/mo'
    page.current_path.must_equal '/supporter/thanks'
    page.body.must_match /You have become a Neocities Supporter/
    @site.reload
    @site.stripe_customer_id.wont_be_nil
    @site.stripe_subscription_id.wont_be_nil
    @site.values[:plan_type].must_equal 'supporter'
    @site.supporter?.must_equal true

    EmailWorker.drain
    mail = Mail::TestMailer.deliveries.first
    mail.subject.must_match "You've become a supporter"
  end
end
