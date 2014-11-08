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

desc "parse logs"
task :parse_logs => [:environment] do
  Dir["/home/web/proxy/logs/*.log"].each do |log_path|
    hits = {}
    visits = {}
    visit_ips = {}

    logfile = File.open log_path, 'r'

    while hit = logfile.gets
      time, username, size, path, ip = hit.split ' '

      hits[username] ||= 0
      hits[username] += 1

      visit_ips[username] = [] if !visit_ips[username]

      unless visit_ips[username].include?(ip)
        visits[username] ||= 0
        visits[username] += 1
        visit_ips[username] << ip
      end
    end

    logfile.close

    hits.each do |username,hitcount|
      DB['update sites set hits=hits+? where username=?', hitcount, username].first
    end

    visits.each do |username,visitcount|
      DB['update sites set views=views+? where username=?', visitcount, username].first
    end

    FileUtils.rm log_path
  end
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

  Zip::File.open(blocked_ips_zip.path) do |zip_file|
    ips = zip_file.glob('listed_ip_90.txt').first.get_input_stream.read
    insert_hashes = []
    ips.each_line {|ip| insert_hashes << {ip: ip.strip, created_at: Time.now}}
    ips = nil

    DB.transaction do
      DB[:blocked_ips].delete
      DB[:blocked_ips].multi_insert insert_hashes
    end
  end
end

desc 'Compile domain map for nginx'
task :compile_domain_map => [:environment] do
  File.open('./files/map.txt', 'w'){|f| Site.exclude(domain: nil).exclude(domain: '').select(:username,:domain).all.collect {|s| f.write "#{s.domain} #{s.username};\n"  }}
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
  Site.exclude(stripe_customer_id: nil).all.each do |site|
    site.plan_type = 'supporter'
    site.save_changes validate: false
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

require 'thread/pool'

desc 'update screenshots'
task :update_screenshots => [:environment] do
  pool = Thread.pool 10
  Site.select(:username).where(site_changed: true, is_banned: false, is_crashing: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.each do |site|
    pool.process { ScreenshotWorker.new.perform site.username, 'index.html' }
  end

  sleep
end

desc 'prime_space_used'
task :prime_space_used => [:environment] do
  Site.select(:id,:username,:space_used).all.each do |s|
    s.space_used += s.actual_space_used
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

=begin
desc 'Update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).filter(is_banned: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.collect {|s|
    ScreenshotWorker.perform_async s.username
  }
end
=end