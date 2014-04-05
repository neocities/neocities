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
  logfile = File.open '/var/log/nginx/neocities-sites.log.1', 'r'
  while hit = logfile.gets
    hit = hit.split ' '

    # It says hits, but really we're tracking visits to index"
    if hit[3] == '/'
      hits[hit[1]] ||= 0
      hits[hit[1]] += 1
    end
  end
  logfile.close

  hits.each do |username,hitcount|
    DB['update sites set hits=hits+? where username=?', hitcount, username].first
  end

end

desc 'Update screenshots'
task :update_screenshots => [:environment] do
  Site.select(:username).filter(is_banned: false).filter(~{updated_at: nil}).order(:updated_at.desc).all.collect {|s|
    ScreenshotWorker.perform_async s.username
  }
end
