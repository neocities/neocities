require_relative './environment.rb'

describe '/admin' do
  include Capybara::DSL

  before do
    Capybara.reset_sessions!
    @admin = Fabricate :site, is_admin: true
    @site = Fabricate :site
    page.set_rack_session id: @admin.id
    visit '/admin'
  end

  describe 'permissions' do
    include Capybara::DSL

    it 'works for admin site' do
      page.body.must_match /Administration/
    end

    it 'fails for site without admin' do
      page.set_rack_session id: @site.id
      visit '/admin'
      page.current_path.must_equal '/'
    end
  end

  describe 'supporter upgrade' do
    include Capybara::DSL

    before do
      @stripe_helper = StripeMock.create_test_helper
      StripeMock.start
      @plan = @stripe_helper.create_plan id: 'special', amount: 0
    end

    after do
      StripeMock.stop
    end

    it 'works for valid site' do
      within(:css, '#upgradeToSupporter') do
        fill_in 'username', with: @site.username
        click_button 'Upgrade to Supporter'
        @site.reload
        @site.stripe_customer_id.wont_be_nil
        @site.stripe_subscription_id.wont_be_nil
        @site.values[:plan_type].must_equal 'special'
        @site.supporter?.must_equal true
      end
    end

  end
end