require "rake/testtask"

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
