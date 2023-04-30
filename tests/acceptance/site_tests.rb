require_relative './environment.rb'

describe 'site page' do
  include Capybara::DSL

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


  describe 'blocking' do
    before do
      @tag = SecureRandom.hex 10
      @blocked_site = Fabricate :site, new_tags_string: @tag, created_at: 2.weeks.ago, site_changed: true, views: Site::BROWSE_MINIMUM_FOLLOWER_VIEWS+1
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
  end

  it '404s if site is banned' do
    site = Fabricate :site
    site.ban!
    visit "/site/#{site.username}"
    _(page.status_code).must_equal 404
    _(page).must_have_content /not found/i
  end
end
