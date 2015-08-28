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

desc 'Update banned IPs list'
task :update_blocked_ips => [:environment] do
  uri = URI.parse('http://www.stopforumspam.com/downloads/listed_ip_90.zip')
  blocked_ips_zip = Tempfile.new('blockedipszip', Dir.tmpdir, 'wb')
  blocked_ips_zip.binmode

  Net::HTTP.start(uri.host, uri.port) do |http|
    resp = http.get(uri.path)
    blocked_ips_zip.write(resp.body)
    blocked_ips_zip.flush
  end

  Zip::Archive.open(blocked_ips_zip.path) do |ar|
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

desc 'Compile domain map for nginx'
task :compile_domain_map => [:environment] do
  File.open('./files/map.txt', 'w') do |file|
    Site.exclude(domain: nil).exclude(domain: '').select(:username,:domain).all.collect do |site|
      file.write ".#{site.domain} #{site.username};\n"
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

desc 'hash_ips'
task :hash_ips => [:environment] do
  Site.select(:id,:ip).order(:id).all.each do |s|
    next if s.ip.nil? || s.ip.match(/#{$config['ip_hash_salt']}/)
    s.ip = s.ip
    s.save_changes validate: false
  end
end

desc 'prime_site_files'
task :prime_site_files => [:environment] do
  Site.where(is_banned: false).select(:id, :username).all.each do |site|
    Dir.glob(File.join(site.files_path, '**/*')).each do |file|
      next unless site.username == 'kyledrake'
      path = file.gsub(site.base_files_path, '').sub(/^\//, '')

      site_file = site.site_files_dataset[path: path]

      if site_file.nil?
        next if File.directory? file
        mtime = File.mtime file
        site.add_site_file(
          path: path,
          size: File.size(file),
          sha1_hash: Digest::SHA1.file(file).hexdigest,
          updated_at: mtime,
          created_at: mtime
        )
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

=begin
desc 'Update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).filter(is_banned: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.collect {|s|
    ScreenshotWorker.perform_async s.username
  }
end
=end
