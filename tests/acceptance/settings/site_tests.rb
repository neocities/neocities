# frozen_string_literal: true
require_relative '../environment.rb'

describe 'site/settings' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  describe 'permissions' do
    before do
      @parent_site = Fabricate :site
      @child_site = Fabricate :site, parent_site_id: @parent_site.id
      @other_site = Fabricate :site
    end

    it 'fails without permissions' do
      page.set_rack_session id: @other_site.id

      visit "/settings/#{@parent_site.username}"
      _(page.current_path).must_equal '/' # This could be better
    end

    it 'allows child site editing from parent' do
      page.set_rack_session id: @parent_site.id
      visit "/settings/#{@child_site.username}"
      _(page.current_path).must_equal "/settings/#{@child_site.username}"
    end
  end

  describe 'changing username' do
    before do
      Capybara.reset_sessions!
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit "/settings/#{@site[:username]}#username"
    end

    after do
      _(Site[username: @site[:username]]).wont_equal nil
    end

    it 'fails for blank username' do
      fill_in 'name', with: ''
      click_button 'Change Name'
      _(page).must_have_content /cannot be blank/i
      _(Site[username: '']).must_be_nil
    end

    it 'fails for subdir periods' do
      fill_in 'name', with: '../hack'
      click_button 'Change Name'
      _(page).must_have_content /Usernames can only contain/i
      _(Site[username: '../hack']).must_be_nil
    end

    it 'fails for same username' do
      fill_in 'name', with: @site.username
      click_button 'Change Name'
      _(page).must_have_content /You already have this name/
    end

    it 'fails for same username with DiFfErEnT CaSiNg' do
      fill_in 'name', with: @site.username.upcase
      click_button 'Change Name'
      _(page).must_have_content /You already have this name/
    end
  end

  describe 'api key' do
    before do
      Capybara.reset_sessions!
      @site = Fabricate :site
      @child_site = Fabricate :site, parent_site_id: @site.id
      page.set_rack_session id: @site.id
    end

    it 'sets api key' do
      visit "/settings/#{@child_site[:username]}#api_key"
      _(@site.api_key).must_be_nil
      _(@child_site.api_key).must_be_nil
      click_button 'Generate API Key'
      _(@site.reload.api_key).must_be_nil
      _(@child_site.reload.api_key).wont_be_nil
      _(page.body).must_match @child_site.api_key
    end

    it 'regenerates api key for child site' do
      visit "/settings/#{@child_site[:username]}#api_key"
      @child_site.generate_api_key!
      api_key = @child_site.api_key
      click_button 'Generate API Key'
      _(@child_site.reload.api_key).wont_equal api_key
    end
  end

  describe 'delete' do
    before do
      Capybara.reset_sessions!
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit "/settings/#{@site[:username]}#delete"
    end

    it 'fails for incorrect entered username' do
      fill_in 'username', with: 'NOPE'
      click_button 'Delete Site'

      _(page.body).must_match /Site user name and entered user name did not match/i
      _(@site.reload.is_deleted).must_equal false
    end

    it 'succeeds' do
      deleted_reason = 'Penelope left a hairball on my site'

      fill_in 'confirm_username', with: @site.username
      fill_in 'deleted_reason', with: deleted_reason
      click_button 'Delete Site'

      @site.reload
      _(@site.is_deleted).must_equal true
      _(@site.deleted_reason).must_equal deleted_reason
      _(page.current_path).must_equal '/'

      _(File.exist?(@site.files_path('./index.html'))).must_equal false
      _(Dir.exist?(@site.files_path)).must_equal false

      path = File.join Site::DELETED_SITES_ROOT, Site.sharding_dir(@site.username), @site.username
      _(Dir.exist?(path)).must_equal true
      _(File.exist?(File.join(path, 'index.html'))).must_equal true

      visit "/site/#{@site.username}"
      _(page.status_code).must_equal 404
    end

    it 'stops charging for supporter account' do
      customer = Stripe::Customer.create(
        source: $stripe_helper.generate_card_token
      )

      subscription = customer.subscriptions.create plan: 'supporter'

      @site.update(
        stripe_customer_id: customer.id,
        stripe_subscription_id: subscription.id,
        plan_type: 'supporter'
      )

      @site.plan_type = subscription.plan.id
      @site.save_changes

      fill_in 'confirm_username', with: @site.username
      fill_in 'deleted_reason', with: 'derp'
      click_button 'Delete Site'

      _(Stripe::Customer.retrieve(@site.stripe_customer_id).subscriptions.count).must_equal 0
      @site.reload
      _(@site.stripe_subscription_id).must_be_nil
      _(@site.is_deleted).must_equal true
    end

    it 'should fail unless owned by current user' do
      someone_elses_site = Fabricate :site
      page.set_rack_session id: @site.id

      page.driver.post "/settings/#{someone_elses_site.username}/delete", {
        username: someone_elses_site.username,
        deleted_reason: 'Dade Murphy enters Acid Burns turf'
      }

      _(page.driver.status_code).must_equal 302
      _(URI.parse(page.driver.response_headers['Location']).path).must_equal '/'
      someone_elses_site.reload
      _(someone_elses_site.is_deleted).must_equal false
    end

    it 'should not show NSFW tab for admin NSFW flag' do
      owned_site = Fabricate :site, parent_site_id: @site.id, admin_nsfw: true
      visit "/settings/#{owned_site.username}"
      _(page.body).wont_match /18\+/
    end

    it 'should succeed if you own the site' do
      owned_site = Fabricate :site, parent_site_id: @site.id
      visit "/settings/#{owned_site.username}#delete"
      fill_in 'confirm_username', with: owned_site.username
      click_button 'Delete Site'

      @site.reload
      owned_site.reload
      _(owned_site.is_deleted).must_equal true
      _(@site.is_deleted).must_equal false

      _(page.current_path).must_equal "/settings"
    end

    it 'fails to delete parent site if children exist' do
      owned_site = Fabricate :site, parent_site_id: @site.id
      visit "/settings/#{@site.username}#delete"
      _(page.body).must_match /You cannot delete the parent site without deleting the children sites first/i
    end
  end

  describe 'bluesky' do
    it 'should set did verification file' do
      Capybara.reset_sessions!
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit "/settings/#{@site.username}#bluesky"
      did = 'did:plc:testexampletest'
      fill_in 'did', with: did
      click_button 'Update DID'
      _(body).must_include 'DID set'
      path = '.well-known/atproto-did'
      _(@site.site_files_dataset.where(path: path).count).must_equal 1
      _(File.read(@site.files_path(path))).must_equal did
    end

    it 'fails with weirdness' do
      Capybara.reset_sessions!
      @site = Fabricate :site
      page.set_rack_session id: @site.id
      visit "/settings/#{@site.username}#bluesky"
      fill_in 'did', with: 'DIJEEDIJSFDSJNFLKJJFN'
      click_button 'Update DID'
      _(body).must_include 'DID was invalid'
      fill_in 'did', with: 'did:plc:'+('a'*50)
      click_button 'Update DID'
      _(body).must_include 'DID provided was too long'
    end
  end
end