require_relative './environment.rb'

def app
  Sinatra::Application
end

describe Site do
  describe 'directory create' do
    it 'handles wacky pathnames' do
      ['/derp', '/derp/'].each do |path|
        site = Fabricate :site
        site_file_count = site.site_files_dataset.count
        site.create_directory path
        site.site_files.select {|s| s.path == '' || s.path == '.'}.length.must_equal 0
        site.site_files.select {|s| s.path == path.gsub('/', '')}.first.wont_be_nil
        site.site_files_dataset.count.must_equal site_file_count+1
      end
    end
  end

  describe 'custom_max_space' do
    it 'should use the custom max space if it is more' do
      site = Fabricate :site
      site.maximum_space.must_equal Site::PLAN_FEATURES[:free][:space]
      site.custom_max_space = 10**9
      site.save_changes
      site.maximum_space.must_equal 10**9
    end
  end

  describe 'can_email' do
    it 'should fail if send_emails is false' do
      site = Fabricate :site
      site.can_email?.must_equal true
      site.update send_emails: false
      site.can_email?.must_equal false
      site.can_email?(:send_comment_emails).must_equal false
      site.update send_emails: true
      site.can_email?(:send_comment_emails).must_equal true
      site.update send_comment_emails: false
      site.can_email?(:send_comment_emails).must_equal false
    end
  end

  describe 'send_email' do
    before do
      EmailWorker.jobs.clear
      @site = Fabricate :site
    end

    it 'works' do
      @site.send_email(subject: 'Subject', body: 'Body')
      EmailWorker.jobs.length.must_equal 1
      args = EmailWorker.jobs.first['args'].first
      args['from'].must_equal Site::FROM_EMAIL
      args['to'].must_equal @site.email
      args['subject'].must_equal 'Subject'
      args['body'].must_equal 'Body'
    end

    it 'fails if send_emails is false' do
      @site.update send_emails: false
      @site.send_email(subject: 'Subject', body: 'Body')
    end
  end

  describe 'plan_name' do
    it 'should set to free for missing stripe_customer_id' do
      site = Fabricate :site
      site.reload.plan_type.must_equal 'free'
    end

    it 'should be free for no plan_type entry' do
      site = Fabricate :site, stripe_customer_id: 'cust_derp'
      site.plan_type.must_equal 'free'
    end

    it 'should match plan_type' do
      %w{supporter free}.each do |plan_type|
        site = Fabricate :site, plan_type: plan_type
        site.plan_type.must_equal plan_type
      end
      site = Fabricate :site, plan_type: nil
      site.plan_type.must_equal 'free'
    end
  end

  describe 'suggestions' do
    it 'should return suggestions for tags' do
      site = Fabricate :site, new_tags_string: 'vegetables'
      Site::SUGGESTIONS_LIMIT.times { Fabricate :site, new_tags_string: 'vegetables' }

      site.suggestions.length.must_equal Site::SUGGESTIONS_LIMIT

      site.suggestions.each {|s| s.tags.first.name.must_equal 'vegetables'}

      site = Fabricate :site, new_tags_string: 'gardening'
      (Site::SUGGESTIONS_LIMIT-5).times {
        Fabricate :site, new_tags_string: 'gardening', views: Site::SUGGESTIONS_VIEWS_MIN
      }

      site.suggestions.length.must_equal Site::SUGGESTIONS_LIMIT
    end
  end
end
