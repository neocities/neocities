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
      @site.profile_comments.count.must_equal 1
      profile_comment = @site.profile_comments.first
      profile_comment.actioning_site.must_equal @commenting_site
      profile_comment.message.must_equal 'I love your site!'
    end

    it 'does not send comment email if not wished' do
      @site.update send_comment_emails: false
      fill_in 'message', with: 'I am annoying'
      click_button 'Post'
      @site.profile_comments.count.must_equal 1
      EmailWorker.jobs.length.must_equal 0
    end

    it 'does not send email if there is none' do
      @site.email = nil
      @site.save_changes validate: false
      fill_in 'message', with: 'DERP'
      click_button 'Post'
      EmailWorker.jobs.length.must_equal 0
    end
  end



  it 'does not allow commenting without requirements met' do
    #site = Fabricate :site
    #commenting_site
    puts "FIXTHIS"
  end

  it '404s for missing site' do
    visit '/site/failderp'
    page.status_code.must_equal 404
    page.must_have_content /not found/i
  end

  it 'loads site page' do
    site = Fabricate :site
    visit "/site/#{site.username}"
    page.status_code.must_equal 200
    page.must_have_content /#{site.username}/
  end

=begin
  it 'allows site blocking' do
    Capybara.default_driver = :poltergeist
    tag = SecureRandom.hex 10
    blocked_site = Fabricate :site, new_tags_string: tag, created_at: 2.weeks.ago, site_changed: true
    site = Fabricate :site

    page.set_rack_session id: site.id

    visit "/browse?tag=#{tag}"

    page.find('.website-Gallery .username a')['href'].must_match /\/site\/#{blocked_site.username}/

    visit "/site/#{blocked_site.username}"

    click_link 'Block'
    click_button 'Block Site'

    visit "/browse?tag=#{tag}"

    page.must_have_content /no active sites found/i

    site.reload
    site.blockings.length.must_equal 1
    site.blockings.first.site_id.must_equal blocked_site.id
  end
=end

  it '404s if site is banned' do
    site = Fabricate :site
    site.ban!
    visit "/site/#{site.username}"
    page.status_code.must_equal 404
    page.must_have_content /not found/i
  end
end
