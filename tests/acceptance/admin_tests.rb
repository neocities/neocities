require_relative './environment.rb'

describe '/admin' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions


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
      _(page.body).must_match /Administration/
    end

    it 'fails for site without admin' do
      page.set_rack_session id: @site.id
      visit '/admin'
      _(page.current_path).must_equal '/'
    end
  end

  describe 'supporter upgrade' do
    include Capybara::DSL

    it 'works for valid site' do
      within(:css, '#upgradeToSupporter') do
        fill_in 'username', with: @site.username
        click_button 'Upgrade to Supporter'
        @site.reload
        _(@site.stripe_customer_id).wont_be_nil
        _(@site.stripe_subscription_id).wont_be_nil
        _(@site.values[:plan_type]).must_equal 'special'
        _(@site.supporter?).must_equal true
      end
    end

  end



  describe 'email blasting' do
    before do
      EmailWorker.jobs.clear
      @admin_site = Fabricate :site, is_admin: true
    end

    it 'works' do
      DB['update sites set changed_count=?', 0].first
      relevant_emails = []

      sites_emailed_count = Site::EMAIL_BLAST_MAXIMUM_PER_DAY*2

      sites_emailed_count.times {
        site = Fabricate :site, updated_at: Time.now, changed_count: 1
        relevant_emails << site.email
      }

      EmailWorker.jobs.clear

      time = Time.now

      Timecop.freeze(time) do
        visit '/admin/email'
        fill_in 'subject', with: 'Subject Test'
        fill_in 'body', with: 'Body Test'
        click_button 'Send'

        relevant_jobs = EmailWorker.jobs.select{|j| relevant_emails.include?(j['args'].first['to']) }
        _(relevant_jobs.length).must_equal sites_emailed_count

        relevant_jobs.each do |job|
          args = job['args'].first
          _(args['from']).must_equal 'Neocities <noreply@neocities.org>'
          _(args['subject']).must_equal 'Subject Test'
          _(args['body']).must_equal 'Body Test'
        end

        _(relevant_jobs.select {|j| j['at'].nil? || j['at'] == Time.now.to_f}.length).must_equal 1
        _(relevant_jobs.select {|j| j['at'] == (Time.now + 0.5).to_f}.length).must_equal 1

        _(relevant_jobs.select {|j| j['at'] == (time+1.day.to_i).to_f}.length).must_equal 1
        _(relevant_jobs.select {|j| j['at'] == (time+1.day.to_i+0.5).to_f}.length).must_equal 1
      end
    end
  end




end
