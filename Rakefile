require "rake/testtask"

desc "Run all tests"
Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['tests/*_test.rb']
  t.verbose = true
end

task :default => :test