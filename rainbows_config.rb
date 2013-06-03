Rainbows! do
  name = 'neocities'

  use :ThreadPool

  client_max_body_size 1*1024*1024 # 1 Megabyte

  worker_processes 8
  worker_connections 32
  timeout 10

  listen "unix:tmp/#{name}.sock", :backlog => 2048

  pid "tmp/#{name}.pid"
  stderr_path "tmp/#{name}.log"
  stdout_path "tmp/#{name}.log"

  preload_app true
 
  before_fork do |server, worker|
    old_pid = "tmp/#{name}.pid.oldbin"
    if File.exists?(old_pid) && server.pid != old_pid
      begin
        Process.kill("QUIT", File.read(old_pid).to_i)
      rescue Errno::ENOENT, Errno::ESRCH
        # someone else did our job for us
      end
    end
  end
  
  after_fork do |server, worker|
    DB.disconnect
  end
end