require 'rake/testtask'

task :environment do
  require './environment.rb'
end

desc "Run all tests"
Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['tests/**/*_tests.rb']
  t.verbose = true
end

task :default => :test

=begin
desc "send domain update email"
task :send_domain_update_email => [:environment] do
  Site.exclude(domain: nil).exclude(domain: '').all.each do |site|
    msg = <<-HERE
MESSAGE GOES HERE TEST
HERE

    site.send_email(
      subject: 'SUBJECT GOES HERE',
      body: msg
    )
  end
end
=end

desc "parse logs"
task :parse_logs => [:environment] do
  Stat.prune!
  StatLocation.prune!
  StatReferrer.prune!
  StatPath.prune!
  Stat.parse_logfiles $config['logs_path']
end

desc 'Update disposable email blacklist'
task :update_disposable_email_blacklist => [:environment] do
  uri = URI.parse('https://raw.githubusercontent.com/martenson/disposable-email-domains/master/disposable_email_blacklist.conf')

  File.write(Site::DISPOSABLE_EMAIL_BLACKLIST_PATH, Net::HTTP.get(uri))
end

desc 'Update banned IPs list'
task :update_blocked_ips => [:environment] do

  IO.copy_stream(
    open('https://www.stopforumspam.com/downloads/listed_ip_90.zip'),
    '/tmp/listed_ip_90.zip'
  )

  Zip::Archive.open('/tmp/listed_ip_90.zip') do |ar|
    ar.fopen('listed_ip_90.txt') do |f|
      ips = f.read
      insert_hashes = []
      ips.each_line {|ip| insert_hashes << {ip: ip.strip, created_at: Time.now}}
      ips = nil

      DB.transaction do
        DB[:blocked_ips].delete
        DB[:blocked_ips].multi_insert insert_hashes
      end
    end
  end
end

desc 'parse tor exits'
task :parse_tor_exits => [:environment] do
  exit_ips = Net::HTTP.get(URI.parse('https://check.torproject.org/exit-addresses'))

  exit_ips.split("\n").collect {|line|
    line.match(/ExitAddress (\d+\.\d+\.\d+\.\d+)/)&.captures&.first
  }.compact

  # ^^ Array of ip addresses of known exit nodes
end

desc 'Compile nginx mapfiles'
task :compile_nginx_mapfiles => [:environment] do
  FileUtils.mkdir_p './files/maps'

  File.open('./files/maps/domains.txt', 'w') do |file|
    Site.exclude(domain: nil).exclude(domain: '').select(:username,:domain).all.each do |site|
      file.write ".#{site.values[:domain]} #{site.username};\n"
    end
  end

  File.open('./files/maps/supporters.txt', 'w') do |file|
    Site.select(:username, :domain).exclude(plan_type: 'free').exclude(plan_type: nil).all.each do |parent_site|
      sites = [parent_site] + parent_site.children
      sites.each do |site|
        file.write "#{site.username}.neocities.org 1;\n"
        unless site.host.match(/\.neocities\.org$/)
          file.write ".#{site.values[:domain]} 1;\n"
        end
      end
    end
  end

  File.open('./files/maps/subdomain-to-domain.txt', 'w') do |file|
    Site.select(:username, :domain).exclude(domain: nil).exclude(domain: '').all.each do |site|
      file.write "#{site.username}.neocities.org #{site.values[:domain]};\n"
    end
  end

  File.open('./files/maps/sandboxed.txt', 'w') do |file|
    usernames = DB["select username from sites where created_at > ? and parent_site_id is null and (plan_type is null or plan_type='free') and is_banned != 't' and is_deleted != 't'", 2.days.ago].all.collect {|s| s[:username]}.each {|username| file.write "#{username} 1;\n"}
  end

  # Compile letsencrypt ssl keys
  sites = DB[%{select username,ssl_key,ssl_cert,domain from sites where ssl_cert is not null and ssl_key is not null and (domain is not null or domain != '') and is_banned != 't' and is_deleted != 't'}].all

  ssl_path = './files/maps/ssl'

  FileUtils.mkdir_p ssl_path

  sites.each do |site|
    [site[:domain], "www.#{site[:domain]}"].each do |domain|
      begin
        key = OpenSSL::PKey::RSA.new site[:ssl_key]
        crt = OpenSSL::X509::Certificate.new site[:ssl_cert]
      rescue => e
        puts "SSL ERROR: #{e.class} #{e.inspect}"
        next
      end

      File.open(File.join(ssl_path, "#{domain}.key"), 'wb') {|f| f.write key.to_der}
      File.open(File.join(ssl_path, "#{domain}.crt"), 'wb') {|f| f.write site[:ssl_cert]}
    end
  end

end

desc 'Produce SSL config package for proxy'
task :buildssl => [:environment] do
  sites = Site.select(:id, :username, :domain, :ssl_key, :ssl_cert).
    exclude(domain: nil).
    exclude(ssl_key: nil).
    exclude(ssl_cert: nil).
    all

  payload = []

  begin
    FileUtils.rm './files/sslsites.zip'
  rescue Errno::ENOENT
  end

  Zip::Archive.open('./files/sslsites.zip', Zip::CREATE) do |ar|
    ar.add_dir 'ssl'

    sites.each do |site|
      ar.add_buffer "ssl/#{site.username}.key", site.ssl_key
      ar.add_buffer "ssl/#{site.username}.crt", site.ssl_cert
      payload << {username: site.username, domain: site.domain}
    end

    ar.add_buffer 'sslsites.json', payload.to_json
  end
end

desc 'Set existing stripe customers to internal supporter plan'
task :primenewstriperunonlyonce => [:environment] do
#  Site.exclude(stripe_customer_id: nil).all.each do |site|
#    site.plan_type = 'supporter'
#    site.save_changes validate: false
#  end

  Site.exclude(stripe_customer_id: nil).where(plan_type: nil).where(plan_ended: false).all.each do |s|
    customer = Stripe::Customer.retrieve(s.stripe_customer_id)
    subscription = customer.subscriptions.first
    next if subscription.nil?
    puts "set subscription id to #{subscription.id}"
    puts "set plan type to #{subscription.plan.id}"
    s.stripe_subscription_id = subscription.id
    s.plan_type = subscription.plan.id
    s.save_changes(validate: false)
  end

end

desc 'Clean tags'
task :cleantags => [:environment] do

  Site.select(:id).all.each do |site|
    if site.tags.length > 5
      site.tags.slice(5, site.tags.length).each {|tag| site.remove_tag tag}
    end
  end

  empty_tag = Tag.where(name: '').first

  if empty_tag
    DB[:sites_tags].where(tag_id: empty_tag.id).delete
  end

  Tag.all.each do |tag|
    if tag.name.length > Tag::NAME_LENGTH_MAX || tag.name.match(/ /)
      DB[:sites_tags].where(tag_id: tag.id).delete
      DB[:tags].where(id: tag.id).delete
    else
      tag.update name: tag.name.downcase.strip
    end
  end

  Tag.all.each do |tag|
    begin
      tag.reload
    rescue Sequel::Error => e
      next if e.message =~ /Record not found/
    end

    matching_tags = Tag.exclude(id: tag.id).where(name: tag.name).all

    matching_tags.each do |matching_tag|
      DB[:sites_tags].where(tag_id: matching_tag.id).update(tag_id: tag.id)
      matching_tag.delete
    end
  end

  Tag.where(name: 'porn').first.update is_nsfw: true
end

desc 'update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).where(site_changed: true, is_banned: false, is_crashing: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.each do |site|
    ScreenshotWorker.perform_async site.username, 'index.html'
  end
end

desc 'rebuild_thumbnails'
task :rebuild_thumbnails => [:environment] do
  dirs = Dir[Site::SITE_FILES_ROOT+'/**/*'].collect {|s| s.sub(Site::SITE_FILES_ROOT, '')}.collect {|s| s.sub('/', '')}
  dirs.each do |d|
    next if File.directory?(d)

    full_path = d.split('/')

    username = full_path.first
    path = '/'+full_path[1..full_path.length].join('/')

    if Pathname(path).extname.gsub('.', '').match Site::IMAGE_REGEX
      begin
        ThumbnailWorker.new.perform username, path
      rescue Magick::ImageMagickError
      end
    end
  end
end

desc 'prime_space_used'
task :prime_space_used => [:environment] do
  Site.select(:id,:username,:space_used).all.each do |s|
    s.space_used = s.actual_space_used
    s.save_changes validate: false
  end
end

desc 'prime site_updated_at'
task :prime_site_updated_at => [:environment] do
  Site.select(:id,:username,:site_updated_at, :updated_at).all.each do |s|
    s.site_updated_at = s.updated_at
    s.save_changes validate: false
  end
end

desc 'prime_site_files'
task :prime_site_files => [:environment] do
  Site.where(is_banned: false).where(is_deleted: false).select(:id, :username).all.each do |site|
    Dir.glob(File.join(site.files_path, '**/*')).each do |file|
      path = file.gsub(site.base_files_path, '').sub(/^\//, '')

      site_file = site.site_files_dataset[path: path]

      if site_file.nil?
        mtime = File.mtime file

        site_file_opts = {
          path: path,
          updated_at: mtime,
          created_at: mtime
        }

        if File.directory? file
          site_file_opts.merge! is_directory: true
        else
          site_file_opts.merge!(
            size: File.size(file),
            sha1_hash: Digest::SHA1.file(file).hexdigest
          )
        end

        site.add_site_file site_file_opts
      end
    end
  end
end

desc 'dedupe_follows'
task :dedupe_follows => [:environment] do
  follows = Follow.all
  deduped_follows = Follow.all.uniq {|f| "#{f.site_id}_#{f.actioning_site_id}"}

  follows.each do |follow|
    unless deduped_follows.include?(follow)
      puts "deleting dedupe: #{follow.inspect}"
      follow.delete
    end
  end
end

desc 'flush_empty_index_sites'
task :flush_empty_index_sites => [:environment] do
  sites = Site.select(:id).all

  counter = 0

  sites.each do |site|
    if site.empty_index?
      counter += 1
      site.site_changed = false
      site.save_changes validate: false
    end
  end

  puts "#{counter} sites set to not changed."
end

desc 'compute_scores'
task :compute_scores => [:environment] do
  Site.compute_scores
end

=begin
desc 'Update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).filter(is_banned: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.collect {|s|
    ScreenshotWorker.perform_async s.username
  }
end
=end

desc 'prime_classifier'
task :prime_classifier => [:environment] do
  Site.select(:id, :username).where(is_banned: false, is_deleted: false).all.each do |site|
    next if site.site_files_dataset.where(classifier: 'spam').count > 0
    html_files = site.site_files_dataset.where(path: /\.html$/).all

    html_files.each do |html_file|
      print "training #{site.username}/#{html_file.path}..."
      site.train html_file.path
      print "done.\n"
    end
  end
end

desc 'train_spam'
task :train_spam => [:environment] do
  paths = File.read('./spam.txt')

  paths.split("\n").each do |path|
    username, site_file_path = path.match(/^([a-zA-Z0-9_\-]+)\/(.+)$/i).captures
    site = Site[username: username]
    next if site.nil?
    site_file = site.site_files_dataset.where(path: site_file_path).first
    next if site_file.nil?
    site.train site_file_path, :spam
    site.ban!
    puts "Deleted #{site_file_path}, banned #{site.username}"
  end
end

desc 'regenerate_ssl_certs'
task :regenerate_ssl_certs => [:environment] do
  sites = DB[%{select id from sites where (domain is not null or domain != '') and is_banned != 't' and is_deleted != 't'}].all

  seconds = 2

  sites.each do |site|
    LetsEncryptWorker.perform_in seconds, site[:id]
    seconds += 10
  end

  puts "#{sites.length.to_s} records are primed"
end

desc 'renew_ssl_certs'
task :renew_ssl_certs => [:environment] do
  delay = 0
  DB[%{select id from sites where (domain is not null or domain != '') and is_banned != 't' and is_deleted != 't' and (cert_updated_at is null or cert_updated_at < ?)}, 60.days.ago].all.each do |site|
    LetsEncryptWorker.perform_in delay.seconds, site[:id]
    delay += 10
  end
end

desc 'purge_tmp_turds'
task :purge_tmp_turds => [:environment] do
  ['neocities_screenshot*', 'RackMultipart*', 'neocities_saving_file*', 'newinstall-*', '*.dmp', 'davfile*', 'magick*', '*.scan', '*.jpg'].each do |target|
    Dir.glob("/tmp/#{target}").select {|filename| File::Stat.new(filename).ctime < (Time.now - 3600)}.each {|filename| FileUtils.rm(filename)}
  end
end

desc 'shard_migration'
task :shard_migration => [:environment] do
  #Site.exclude(is_deleted: true).exclude(is_banned: true).select(:username).each do |site|
  #  FileUtils.mkdir_p File.join('public', 'testsites', site.username)
  #end
  #exit
  Dir.chdir('./public/testsites')
  Dir.glob('*').each do |dir|
    sharding_dir = Site.sharding_dir(dir)
    FileUtils.mkdir_p File.join('..', 'newtestsites', sharding_dir)
    FileUtils.mv dir, File.join('..', 'newtestsites', sharding_dir)
  end
  sleep 1
  FileUtils.rmdir './public/testsites'
  sleep 1
  FileUtils.mv './public/newtestsites', './public/testsites'
end

desc 'compute_follow_count_scores'
task :compute_follow_count_scores => [:environment] do

  Site.select(:id,:username,:follow_count).all.each do |site|
    count = site.scorable_follow_count

    if count != 0
      puts "#{site.username} #{site.follow_count} => #{count}"
    end
    DB['update sites set follow_count=? where id=?', count, site.id].first
  end
end

desc 'prime_redis_proxy_ssl'
task :prime_redis_proxy_ssl => [:environment] do
  site_ids = DB[%{
    select id from sites where domain is not null and ssl_cert is not null and ssl_key is not null
    and is_deleted != ? and is_banned != ?
  }, true, true].all.collect {|site_id| site_id[:id]}

  site_ids.each do |site_id|
    Site[site_id].store_ssl_in_redis_proxy
  end
end

desc 'dedupe_site_blocks'
task :dedupe_site_blocks => [:environment] do
  duped_blocks = []
  block_ids = Block.select(:id).all.collect {|b| b.id}
  block_ids.each do |block_id|
    next unless duped_blocks.select {|db| db.id == block_id}.empty?
    block = Block[block_id]
    if block
      blocks = Block.exclude(id: block.id).where(site_id: block.site_id).where(actioning_site_id: block.actioning_site_id).all
      duped_blocks << blocks
      duped_blocks.flatten!
    end
  end

  duped_blocks.each do |duped_block|
    duped_block.destroy
  end
end

desc 'ml_screenshots_list_dump'
task :ml_screenshots_list_dump => [:environment] do
  ['phishing', 'spam', 'ham', nil].each do |classifier|
    File.open("./files/screenshot-urls-#{classifier.to_s}.txt", 'w') do |fp|
      SiteFile.where(classifier: classifier).where(path: 'index.html').each do |site_file|
        begin
          fp.write "#{site_file.site.screenshot_url('index.html', Site::SCREENSHOT_RESOLUTIONS.first)}\n"
        rescue NoMethodError
        end
      end
    end
  end
end

desc 'generate_sitemap'
task :generate_sitemap => [:environment] do
  sorted_sites = {}

  sites = Site.
    select(:id, :username, :updated_at).
    where(site_changed: true).
    exclude(updated_at: nil).
    order(:follow_count.desc, :updated_at.desc).
    all

  sitemap_root = File.join Site::PUBLIC_ROOT, 'sitemap'
  FileUtils.mkdir_p sitemap_root

  sites.each do |site|
    sharding_dir = Site.sharding_dir site.username
    key = sharding_dir.split('/').first

    site_urlset_path = File.join(sitemap_root, key, "#{site.username}.xml")

    if site.is_deleted
      FileUtils.rm site_urlset_path if File.exist? site_urlset_path
      next
    end

    builder = Nokogiri::XML::Builder.new { |xml|
      xml.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
        site.site_files_dataset.where(path: /\.html?$/).all.each { |site_file|
          xml.url {
            xml.loc site.file_uri site_file.path
            xml.lastmod site_file.updated_at.strftime("%Y-%m-%d")
          }
        }
      }
    }

    FileUtils.mkdir_p File.join(sitemap_root, key)
    File.write site_urlset_path, builder.to_xml(encoding: 'UTF-8')

    sorted_sites[key] ||= []
    sorted_sites[key] << site
  end
  sites = nil
  GC.start

  # Create XML file for each site
  sorted_sites.keys.sort.each { |key|
    builder = Nokogiri::XML::Builder.new { |xml|
      xml.sitemapindex(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
        sorted_sites[key].each { |site|
          next if site.is_deleted
          xml.sitemap {
            xml.loc "https://neocities.org/sitemap/#{key}/#{site.username}.xml"
            xml.lastmod site.updated_at.strftime("%Y-%m-%d")
          }
        }
      }
    }

    File.write File.join(sitemap_root, "index-#{key}.xml"), builder.to_xml(encoding: 'UTF-8')
  }

  # Create root sitemap index that links to the other ones
  builder = Nokogiri::XML::Builder.new { |xml|
    xml.sitemapindex(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
      sorted_sites.keys.sort.each { |key|
        xml.sitemap {
          xml.loc "https://neocities.org/sitemap/index-#{key}.xm"
          xml.lastmod Time.now.strftime("%Y-%m-%d")
        }
      }
    }
  }
  File.write File.join(sitemap_root, "index.xml"), builder.to_xml(encoding: 'UTF-8')

  # Set basic neocities.org root paths
  builder = Nokogiri::XML::Builder.new { |xml|
    xml.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
      File.read(File.join(DIR_ROOT, 'files', 'root_site_uris.txt')).each_line { |uri|
        xml.url {
          xml.loc uri.strip
        }
      }
    }
  }

  File.write File.join(sitemap_root, 'index-root.xml'), builder.to_xml(encoding: 'UTF-8')

=begin
    Zlib::GzipWriter.open File.join(sitemap_root, "index-#{key}.xml.gz") do |gz|
      gz.write builder.to_xml(encoding: 'UTF-8')
    end
=end
end
