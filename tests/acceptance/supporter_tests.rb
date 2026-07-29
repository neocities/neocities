# frozen_string_literal: true
require_relative './environment.rb'

describe '/supporter' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  before do
    Capybara.default_driver = :selenium_chrome_headless
    Capybara.reset_sessions!

    @site = Fabricate :site
    page.set_rack_session id: @site.id
    EmailWorker.jobs.clear
    Mail::TestMailer.deliveries.clear
  end

  after do
    Capybara.default_driver = :rack_test
  end

  #it 'should work for paypal' do
  #end

  it 'allows masked card details through browser pattern validation' do
    visit '/supporter'

    find('#cardnumber').set '4242424242424242'
    find('#expirationdate').set '0127'
    find('#securitycode').set '123'

    _(find('#cardnumber').value).must_equal '4242 4242 4242 4242'
    _(find('#expirationdate').value).must_equal '01/27'
    _(page.evaluate_script("document.getElementById('cardnumber').validity.patternMismatch")).must_equal false
    _(page.evaluate_script("document.getElementById('expirationdate').validity.patternMismatch")).must_equal false
  end

  # FIXME
=begin
  it 'should work for fresh signup' do
    visit '/supporter'
    find('.cc-number input[type=text]').set '4242424242424242'
    all('.cc-exp input[type=text]').first.set '01'
    all('.cc-exp input[type=text]').last.set Date.today.next_year.year.to_s[2..3]
    find('.cc-name').set 'Penelope'
    all('.flip-tab').first.click
    find('.cc-cvc').set '123'
    page.evaluate_script("document.getElementById('stripe_token').value = '#{$stripe_helper.generate_card_token}'")
    click_link 'Upgrade for $5/mo'
    _(page.current_path).must_equal '/supporter'
    all('.txt-Center')
    _(page.body).must_match /You have become a Neocities Supporter/
    @site.reload
    _(@site.stripe_customer_id).wont_be_nil
    _(@site.stripe_subscription_id).wont_be_nil
    _(@site.values[:plan_type]).must_equal 'supporter'
    _(@site.supporter?).must_equal true

    EmailWorker.drain
    mail = Mail::TestMailer.deliveries.first
    _(mail.subject).must_match "You've become a supporter"
  end
=end
end