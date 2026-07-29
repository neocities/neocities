# frozen_string_literal: true
require_relative './environment.rb'

describe 'site page' do
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  after do
    Capybara.default_driver = :rack_test
  end

  describe 'commenting' do
    before do
      @site = Fabricate :site
      @commenting_site = Fabricate :site, commenting_allowed: true
      page.set_rack_session id: @commenting_site.id
      visit "/site/#{@site.username}"
      EmailWorker.jobs.clear
    end

    it 'allows commenting' do
      fill_in 'message', with: 'I love your site!'
      click_button 'Post'
      _(@site.profile_comments.count).must_equal 1
      profile_comment = @site.profile_comments.first
      _(profile_comment.actioning_site.id).must_equal @commenting_site.id
      _(profile_comment.message).must_equal 'I love your site!'
    end

    it 'does not send comment email if not wished' do
      @site.update send_comment_emails: false
      fill_in 'message', with: 'I am annoying'
      click_button 'Post'
      _(@site.profile_comments.count).must_equal 1
      _(EmailWorker.jobs.length).must_equal 0
    end

    it 'does not send email if there is none' do
      @site.email = nil
      @site.save_changes validate: false
      fill_in 'message', with: 'DERP'
      click_button 'Post'
      _(EmailWorker.jobs.length).must_equal 0
    end
  end



  it 'does not allow commenting without requirements met' do
    #site = Fabricate :site
    #commenting_site
    puts "FIXTHIS"
  end

  it '404s for missing site' do
    visit '/site/failderp'
    _(page.status_code).must_equal 404
    _(page).must_have_content /not found/i
  end

  it 'loads site page' do
    site = Fabricate :site
    visit "/site/#{site.username}"
    _(page.status_code).must_equal 200
    _(page).must_have_content /#{site.username}/
  end

  it 'does not double escape titles in the document head' do
    site = Fabricate :site
    site.update title: "alice's alcove"

    visit "/site/#{site.username}"

    _(page.title).must_equal "Neocities - alice's alcove"
    _(page.html).wont_include 'alice&amp;#39;s alcove'
    _(page.html).wont_include "#{site.username}&amp;#39;s Neocities site profile"
  end


  describe 'blocking' do
    before do
      @tag = SecureRandom.hex 10
      @blocked_site = Fabricate :site, new_tags_string: @tag, created_at: 1.year.ago, site_changed: true, views: Site::BROWSE_MINIMUM_FOLLOWER_VIEWS+1, follow_count: Site::BROWSE_FOLLOWER_MINIMUM_FOLLOWS+1
    end

    after do
      @blocked_site.destroy
    end

    it 'allows site blocking and unblocking' do
      site = Fabricate :site

      page.set_rack_session id: site.id

      visit "/browse?tag=#{@tag}"

      _(page.find('.website-Gallery .username a')['href']).must_match /\/site\/#{@blocked_site.username}/

      visit "/site/#{@blocked_site.username}"

      click_link 'Block'
      click_button 'Block Site'

      visit "/browse?tag=#{@tag}"

      _(page).must_have_content /no active sites found/i

      site.reload
      _(site.blockings.length).must_equal 1
      _(site.blockings.first.site_id).must_equal @blocked_site.id

      visit "/site/#{@blocked_site.username}"

      click_link 'Unblock'

      visit "/browse?tag=#{@tag}"
      _(page.find('.website-Gallery .username a')['href']).must_match /\/site\/#{@blocked_site.username}/
    end

    it 'removes follows/followings when blocking' do
      site = Fabricate :site
      not_blocked_site = Fabricate :site
      blocked_site = Fabricate :site

      site.add_follow actioning_site: not_blocked_site
      site.add_following site: not_blocked_site

      site.add_follow actioning_site: blocked_site
      site.add_following site: blocked_site

      _(site.follows.count).must_equal 2
      _(site.followings.count).must_equal 2

      page.set_rack_session id: site.id

      visit "/site/#{blocked_site.username}"

      click_link 'Block'
      click_button 'Block Site'

      _(site.follows.count).must_equal 1
      _(site.followings.count).must_equal 1

      _(site.follows.count {|s| s.actioning_site == blocked_site}).must_equal 0
      _(site.followings.count {|s| s.site == blocked_site}).must_equal 0

    end
  end

  it '404s if site is banned' do
    site = Fabricate :site
    site.ban!
    visit "/site/#{site.username}"
    _(page.status_code).must_equal 404
    _(page).must_have_content /not found/i
  end

  describe 'stats page' do
    before do
      Capybara.reset_sessions!
    end

    it 'requires login and hides the traffic link from visitors' do
      site = Fabricate :site

      visit "/site/#{site.username}"
      _(page).wont_have_link 'Site Traffic Stats'

      visit "/site/#{site.username}/stats"
      _(page.current_path).must_equal '/'
    end

    it '404s for a logged-in user who does not control the site' do
      site = Fabricate :site
      other_site = Fabricate :site
      page.set_rack_session id: other_site.id

      visit "/site/#{site.username}/stats"

      _(page.status_code).must_equal 404
      _(page).must_have_content /not found/i
    end

    it 'allows the controlling account to view a child site stats page' do
      owner = Fabricate :site
      child_site = Fabricate :site, parent_site_id: owner.id
      page.set_rack_session id: owner.id

      visit "/site/#{child_site.username}/stats"

      _(page.status_code).must_equal 200
      _(page).must_have_selector 'h1', text: "Traffic for #{child_site.host}"
    end

    it 'allows an admin to view another site stats page' do
      site = Fabricate :site, plan_type: 'supporter'
      admin = Fabricate :site, is_admin: true
      page.set_rack_session id: admin.id

      visit "/site/#{site.username}"
      _(page).must_have_link 'Site Traffic Stats', href: "/site/#{site.username}/stats"

      visit "/site/#{site.username}/stats?days=30"

      _(page.status_code).must_equal 200
      _(page).must_have_selector 'h1', text: "Traffic for #{site.host}"
      _(page.find('.stats-range [aria-current="page"]').text).must_equal '30 days'
      _(page).must_have_link 'Download CSV', href: '?days=30&format=csv'
    end

    it 'shows a clear traffic summary and definitions' do
      site = Fabricate :site
      site.add_stat created_at: Date.today - 2, hits: 12, views: 3
      site.add_stat created_at: Date.today - 1, hits: 18, views: 5
      page.set_rack_session id: site.id

      visit "/site/#{site.username}/stats"

      _(page.status_code).must_equal 200
      _(page).must_have_selector 'h1', text: "Traffic for #{site.host}"
      _(page.find('.stats-metric-visits .stats-metric-value').text).must_equal '8'
      _(page.find('.stats-metric-hits .stats-metric-value').text).must_equal '30'
      _(page.find('.stats-metric-average .stats-metric-value').text).must_equal '4'
      _(page).must_have_selector '.stats-chart-legend', text: 'Visits Hits'
      _(page).must_have_content 'A visit is one unique IP address requesting pages within an hour.'
      _(page).must_have_content 'One page view usually creates several hits.'
    end

    it 'shows date controls and CSV export to a supporter site owner' do
      site = Fabricate :site, plan_type: 'supporter'
      page.set_rack_session id: site.id

      visit "/site/#{site.username}/stats?days=30"

      _(page).must_have_link '30 days', href: '?days=30'
      _(page.find('.stats-range [aria-current="page"]').text).must_equal '30 days'
      _(page).must_have_link 'Download CSV', href: '?days=30&format=csv'
    end

    it 'shows an empty state when there are no completed traffic days' do
      site = Fabricate :site
      page.set_rack_session id: site.id

      visit "/site/#{site.username}/stats"

      _(page).must_have_content 'No traffic to chart yet'
      _(page).wont_have_selector '#traffic-chart'
    end

    it 'handles large days parameter without exception' do
      site = Fabricate :site
      page.set_rack_session id: site.id
      visit "/site/#{site.username}/stats?days=3000000000000000000000000000"
      _(page.status_code).must_equal 200
      _(page).must_have_content 'Last 7 days'
    end

    it 'defaults non-positive day ranges without exception' do
      site = Fabricate :site, plan_type: 'supporter'
      page.set_rack_session id: site.id

      [0, -1].each do |days|
        visit "/site/#{site.username}/stats?days=#{days}"
        _(page.status_code).must_equal 200
        _(page).must_have_content 'Last 7 days'
      end
    end
  end
end
