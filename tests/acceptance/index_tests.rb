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
      page.body.must_match /Thanks for joining the Neocities community/i
      page.body.wont_match /You aren’t following any websites yet/i
    end

    it 'displays a follow and an unrelated follow' do
      @followed_site = Fabricate :site
      @site.toggle_follow @followed_site
      @another_site = Fabricate :site
      @followed_site.toggle_follow @another_site
      visit '/'
      find('.news-item', match: :first).text.must_match /#{@followed_site.username} followed #{@another_site.username}/i
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
      find('.news-item').text.must_match /you followed #{@followed_site.username}/i
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

  describe 'username lookup' do
    before do
      @site = Fabricate :site
      Capybara.reset_sessions!
      EmailWorker.jobs.clear

      visit '/signin'
      click_link 'I forgot my username.'
    end

    it 'works for valid email' do
      page.current_url.must_match /\/forgot_username$/
      fill_in :email, with: @site.email
      click_button 'Find username'
      URI.parse(page.current_url).path.must_equal '/'
      page.must_have_content 'If your email was valid, the Neocities Cat will send an e-mail with your username in it'
      email_args = EmailWorker.jobs.first['args'].first
      email_args['to'].must_equal @site.email
      email_args['subject'].must_match /username lookup/i
      email_args['body'].must_match /your username is #{@site.username}/i
    end

    it 'fails silently for unknown email' do
      fill_in :email, with: 'N-O-P-E@example.com'
      click_button 'Find username'
      URI.parse(page.current_url).path.must_equal '/'
      page.must_have_content 'If your email was valid, the Neocities Cat will send an e-mail with your username in it'
      EmailWorker.jobs.length.must_equal 0
    end

    it 'fails for no input' do
      click_button 'Find username'
      URI.parse(page.current_url).path.must_equal '/forgot_username'
      page.must_have_content 'Cannot use an empty email address'
    end
  end
end
