require_relative './environment.rb'

describe 'site page' do
  include Capybara::DSL

  after do
    Capybara.default_driver = :rack_test
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

  it 'allows site blocking' do
    Capybara.default_driver = :poltergeist
    tag = SecureRandom.hex 10
    blocked_site = Fabricate :site, new_tags_string: tag, created_at: 2.weeks.ago, site_changed: true
    site = Fabricate :site

    page.set_rack_session id: site.id

    visit "/browse?tag=#{tag}"

    page.find('.website-Gallery .title a')['href'].must_match /\/surf\/#{blocked_site.username}/

    visit "/site/#{blocked_site.username}"

    click_link 'Block'
    click_button 'Block Site'

    visit "/browse?tag=#{tag}"

    page.must_have_content /no active sites found/i

    site.reload
    site.blockings.length.must_equal 1
    site.blockings.first.site_id.must_equal blocked_site.id
  end

  it '404s if site is banned' do
    site = Fabricate :site
    site.ban!
    visit "/site/#{site.username}"
    page.status_code.must_equal 404
    page.must_have_content /not found/i
  end
end