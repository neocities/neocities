require_relative './environment.rb'

describe '/supporter' do
  include Capybara::DSL

  before do
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
  end

  it 'should work for paypal' do

  end

  it 'should work for fresh signup' do
    visit '/supporter'
    fill_in 'Card Number', with: '4242424242424242'
    fill_in 'Expiration Month', with: '01'
    fill_in 'Expiration Year', with: Date.today.next_year
    fill_in 'Cardholder\'s Name', with: 'Penelope'
    fill_in 'Card Validation Code', with: '123'
    find('#stripe_token').set @stripe_helper.generate_card_token
    #find('#upgradePlanType').set 'supporter'
    click_link 'Upgrade for'
    page.current_path.must_equal '/supporter/thanks'
    page.body.must_match /You now have the Supporter plan./
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
