# frozen_string_literal: true
require_relative './environment.rb'

def app
  Sinatra::Application
end

describe Site do
  describe 'username' do
    it 'only passes valid hostnames for username' do
      _(Site.valid_username?('|\|0p|E')).must_equal false
      _(Site.valid_username?('nope-')).must_equal false
      _(Site.valid_username?('-nope')).must_equal false
      _(Site.valid_username?('do-pe')).must_equal true
      _(Site.valid_username?('d')).must_equal true
      _(Site.valid_username?('do')).must_equal true
    end
  end

  describe 'child sites' do
    it 'child sites do not require email validation' do
      parent_site = Fabricate :site, email: 'parent@example.com', email_confirmed: false
      child_site = Fabricate :site, parent_site_id: parent_site.id, email: nil

      _(parent_site.parent?).must_equal true
      _(child_site.parent?).must_equal false
      
      # Parent site needs email validation, child site does not
      _(parent_site.email_not_validated?).must_equal true
      _(child_site.email_not_validated?).must_equal false
    end
  end

  describe 'email validation' do
    it 'accepts valid email addresses' do
      valid_emails = [
        'user@example.com',
        'test.email@domain.org',
        'user+tag@example.com',
        'user_name@domain.co.uk',
        'user-name@example-domain.com',
        'user@xn--1lqs71d.xn--wgv71a',
        'a.very.long.email.address@long-domain-name.example.com'
      ]

      valid_emails.each do |email|
        site = Fabricate.build(:site, email: email)
        site.valid?
        email_errors = site.errors[:email] || []
        format_errors = email_errors.select { |e| e.include?('valid email') }
        _(format_errors).must_be_empty
      end
    end

    it 'rejects invalid email addresses' do
      invalid_emails = [
        'user@domain.com💩💩💩',
        'user@domain.com extra text',
        'user @domain.com',
        'user@domain',
        'user@domain.',
        '@domain.com',
        'user@',
        'plaintext',
      ]

      invalid_emails.each do |email|
        site = Fabricate.build(:site, email: email)
        site.valid?
        email_errors = site.errors[:email] || []
        format_errors = email_errors.select { |e| e.include?('valid email') }
        _(format_errors).wont_be_empty
      end
    end

    it 'rejects emails that exceed byte length limit' do
      long_email = 'user@example.com' + 'a' * 300 # Will exceed 254 byte limit
      site = Fabricate.build(:site, email: long_email)
      site.valid?

      email_errors = site.errors[:email] || []
      length_errors = email_errors.select { |e| e.include?('too long') }
      _(length_errors).wont_be_empty
    end

    it 'rejects emails with unicode padding that exceed byte limit' do
      unicode_email = 'user@example.com' + '⠀' * 100 # Braille blank chars
      _(unicode_email.bytesize).must_be :>, Site::MAX_EMAIL_LENGTH

      site = Fabricate.build(:site, email: unicode_email)
      site.valid?

      email_errors = site.errors[:email] || []
      length_errors = email_errors.select { |e| e.include?('too long') }
      _(length_errors).wont_be_empty
    end

    it 'accepts emails just under the byte limit' do
      under_limit_email = 'a' * (Site::MAX_EMAIL_LENGTH - 15) + '@example.com'
      _(under_limit_email.bytesize).must_be :<=, Site::MAX_EMAIL_LENGTH

      site = Fabricate.build(:site, email: under_limit_email)
      site.valid?

      email_errors = site.errors[:email] || []
      length_errors = email_errors.select { |e| e.include?('too long') }
      _(length_errors).must_be_empty
    end
  end

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

    it 'scrubs ../ from directory' do
      site = Fabricate :site
      site.create_directory '../../test'
      _(site.site_files.select {|site_file| site_file.path =~ /\.\./}.length).must_equal 0
    end

    it 'blocks long directory create' do
      site = Fabricate :site
      long_path_string = 'a' * (SiteFile::FILE_PATH_CHARACTER_LIMIT + 1)
      res = site.create_directory long_path_string
      _(res).must_equal 'Directory path is too long.'
    end

    it 'blocks individual directory names that are too long' do
      site = Fabricate :site
      long_dir_name = 'a' * (SiteFile::FILE_NAME_CHARACTER_LIMIT + 1)
      res = site.create_directory "somedir/#{long_dir_name}/anotherdir"
      _(res).must_match /name is too long/i
    end
  end

  describe 'scrubbed_path' do
    it 'preserves literal percent characters without URL decoding' do
      site = Fabricate :site

      test_paths = [
        '100% awesome.jpg',
        'derpking/70%off.png',
        '50% sale.txt',
        'discount%special.png',
        'garfield is 100% sexy.jpg',
        'path/with/100%valid.txt'
      ]

      test_paths.each do |path|
        scrubbed = site.scrubbed_path(path)
        _(scrubbed).must_equal path  # Should be exactly the same - no URL decoding
      end
    end

    it 'still handles path traversal and other security issues' do
      site = Fabricate :site

      # Should still block path traversal
      _(site.scrubbed_path('../../../etc/passwd')).must_equal 'etc/passwd'
      _(site.scrubbed_path('../../test')).must_equal 'test'

      # Should still remove empty components and dots
      _(site.scrubbed_path('/./test/./file.txt')).must_equal 'test/file.txt'
      _(site.scrubbed_path('test//file.txt')).must_equal 'test/file.txt'

      # But percent characters should be preserved
      _(site.scrubbed_path('test/70%off.png')).must_equal 'test/70%off.png'
    end

    it 'raises error for control characters' do
      site = Fabricate :site

      # Should still raise error for control characters (below ASCII 32)
      _(proc { site.scrubbed_path("test\x00file.txt") }).must_raise ArgumentError
      _(proc { site.scrubbed_path("test\x1Ffile.txt") }).must_raise ArgumentError
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
      Site::SUGGESTIONS_LIMIT.times { Fabricate :site, new_tags_string: 'vegetables', site_changed: true }

      _(site.suggestions.length).must_equal Site::SUGGESTIONS_LIMIT

      site.suggestions.each do |suggestion|
        _(suggestion.tags.first.name).must_equal 'vegetables'
      end

      site = Fabricate :site, new_tags_string: 'gardening'
      (Site::SUGGESTIONS_LIMIT-5).times {
        Fabricate :site, new_tags_string: 'gardening', views: Site::SUGGESTIONS_VIEWS_MIN, site_changed: true
      }

      _(site.suggestions.length).must_equal(Site::SUGGESTIONS_LIMIT)
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