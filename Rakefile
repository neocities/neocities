require 'rake/testtask'

task :environment do
  require './environment.rb'
end

desc "Run all tests"
Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['tests/*_tests.rb']
  t.verbose = true
end

task :default => :test

desc "parse logs"
task :parse_logs => [:environment] do
  hits = {}
  visits = {}
  visit_ips = {}

  logfile = File.open '/var/log/nginx/neocities-sites.log.1', 'r'

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
end

desc 'Update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).filter(is_banned: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.collect {|s|
    ScreenshotWorker.perform_async s.username
  }
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
