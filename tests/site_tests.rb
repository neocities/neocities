require_relative './environment.rb'

def app
  Sinatra::Application
end

describe Site do
  describe 'banning' do
    it 'still makes files available' do
      site = Fabricate :site
      site.ban!
      _(File.exist?(site.current_files_path('index.html'))).must_equal true
      _(site.current_files_path('index.html')).must_equal File.join(Site::DELETED_SITES_ROOT, Site.sharding_dir(site.username), site.username, 'index.html')
    end
  end

  describe 'unban' do
    it 'works' do
      site = Fabricate :site
      index_path = File.join site.base_files_path, 'index.html'
      site.ban!
      _(File.exist?(index_path)).must_equal false
      site.unban!
      site.reload
      _(site.is_banned).must_equal false
      _(site.banned_at).must_be_nil
      _(site.blackbox_whitelisted).must_equal true
      _(File.exist?(index_path)).must_equal true
    end
  end

  describe 'directory create' do
    it 'handles wacky pathnames' do
      ['/derp', '/derp/'].each do |path|
        site = Fabricate :site
        site_file_count = site.site_files_dataset.count
        site.create_directory path
        _(site.site_files.select {|s| s.path == '' || s.path == '.'}.length).must_equal 0
        _(site.site_files.select {|s| s.path == path.gsub('/', '')}.first).wont_be_nil
        _(site.site_files_dataset.count).must_equal site_file_count+1
      end
    end
  end

  describe 'custom_max_space' do
    it 'should use the custom max space if it is more' do
      site = Fabricate :site
      _(site.maximum_space).must_equal Site::PLAN_FEATURES[:free][:space]
      site.custom_max_space = 10**9
      site.save_changes
      _(site.maximum_space).must_equal 10**9
    end
  end

  describe 'can_email' do
    it 'should fail if send_emails is false' do
      site = Fabricate :site
      _(site.can_email?).must_equal true
      site.update send_emails: false
      _(site.can_email?).must_equal false
      _(site.can_email?(:send_comment_emails)).must_equal false
      site.update send_emails: true
      _(site.can_email?(:send_comment_emails)).must_equal true
      site.update send_comment_emails: false
      _(site.can_email?(:send_comment_emails)).must_equal false
    end
  end

  describe 'send_email' do
    before do
      EmailWorker.jobs.clear
      @site = Fabricate :site
    end

    it 'works' do
      @site.send_email(subject: 'Subject', body: 'Body')
      _(EmailWorker.jobs.length).must_equal 1
      args = EmailWorker.jobs.first['args'].first
      _(args['from']).must_equal Site::FROM_EMAIL
      _(args['to']).must_equal @site.email
      _(args['subject']).must_equal 'Subject'
      _(args['body']).must_equal 'Body'
    end

    it 'fails if send_emails is false' do
      @site.update send_emails: false
      @site.send_email(subject: 'Subject', body: 'Body')
    end
  end

  describe 'plan_name' do
    it 'should set to free for missing stripe_customer_id' do
      site = Fabricate :site
      _(site.reload.plan_type).must_equal 'free'
    end

    it 'should be free for no plan_type entry' do
      site = Fabricate :site, stripe_customer_id: 'cust_derp'
      _(site.plan_type).must_equal 'free'
    end

    it 'should match plan_type' do
      %w{supporter free}.each do |plan_type|
        site = Fabricate :site, plan_type: plan_type
        _(site.plan_type).must_equal plan_type
      end
      site = Fabricate :site, plan_type: nil
      _(site.plan_type).must_equal 'free'
    end
  end

  describe 'suggestions' do
    it 'should return suggestions for tags' do
      site = Fabricate :site, new_tags_string: 'vegetables'
      Site::SUGGESTIONS_LIMIT.times { Fabricate :site, new_tags_string: 'vegetables' }

      _(site.suggestions.length).must_equal Site::SUGGESTIONS_LIMIT

      site.suggestions.each do |suggestion|
        _(suggestion.tags.first.name).must_equal 'vegetables'
      end

      site = Fabricate :site, new_tags_string: 'gardening'
      (Site::SUGGESTIONS_LIMIT-5).times {
        Fabricate :site, new_tags_string: 'gardening', views: Site::SUGGESTIONS_VIEWS_MIN
      }

      _(site.suggestions.length).must_equal(Site::SUGGESTIONS_LIMIT - 5)
    end
  end

  describe 'purge_cache' do
    before do
      @site = Fabricate :site
      PurgeCacheWorker.jobs.clear
    end
    it 'works for /index.html' do
      @site.purge_cache '/index.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/'
    end

    it 'works for /dir/index.html' do
      @site.purge_cache '/dir/index.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/dir/'
    end

    it 'works for /test.html' do
      @site.purge_cache '/test.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/test'
    end

    it 'works for /newdir/index.html' do
      @site.purge_cache '/newdir/test.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/newdir/test'
    end

    it 'works for /file.png' do
      @site.purge_cache '/file.png'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/file.png'
    end

    it 'works for /testdir/file.png' do
      @site.purge_cache '/testdir/file.png'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/testdir/file.png'
    end

    it 'works for /notindex.html' do
      @site.purge_cache '/notindex.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/notindex'
    end

    it 'works for index.html missing forward slash' do
      @site.purge_cache 'index.html'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/'
    end

    it 'works for photo.png missing forward slash' do
      @site.purge_cache 'photo.png'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/photo.png'
    end

    it 'works for testdir/photo.png missing forward slash' do
      @site.purge_cache 'testdir/photo.png'
      _(PurgeCacheWorker.jobs.length).must_equal 1
      args = PurgeCacheWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal '/testdir/photo.png'
    end
  end
end