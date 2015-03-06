require_relative './environment.rb'

describe '/' do
  include Capybara::DSL

  describe 'news feed' do
    before do
      @site = Fabricate :site
      page.set_rack_session id: @site.id
    end

    it 'loads the news feed with welcome' do
      visit '/'
      page.body.must_match /Neocities news feed/i
      page.body.must_match /You aren’t following any websites yet/i
    end

    it 'displays a follow and an unrelated follow' do
      @followed_site = Fabricate :site
      @site.toggle_follow @followed_site
      @another_site = Fabricate :site
      @followed_site.toggle_follow @another_site
      visit '/'
      find('.news-item', match: :first).text.must_match /#{@followed_site.username} started following the site of #{@another_site.username}/i
    end

    it 'loads my activities only' do
      @followed_site = Fabricate :site
      @site.toggle_follow @followed_site
      @another_site = Fabricate :site
      @followed_site.toggle_follow @another_site
      visit '/?activity=mine'
      find('.news-item').text.must_match //i
    end

    it 'loads a specific event with the id' do
      @followed_site = Fabricate :site
      @site.toggle_follow @followed_site
      visit "/?event_id=#{@followed_site.events.first.id}"
      find('.news-item').text.must_match /you started following the site of #{@followed_site.username}/i
    end
  end

  describe 'static pages' do
    include Capybara::DSL

    it 'loads static info pages' do
      links = [
        ['About', 'about'],
        ['Learn', 'tutorials'],
        ['Donate', 'donate'],
        ['API', 'api'],
        ['Terms', 'terms'],
        ['Privacy', 'privacy'],
        ['Press', 'press']
      ]

      links.each do |l|
        visit '/'
        find('a', text: l.first, match: :first).click
        page.status_code.must_equal 200
        page.current_path.must_equal "/#{l.last}"
      end
    end
  end
end
