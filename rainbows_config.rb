Rainbows! do
  use :ThreadPool

  client_max_body_size 100*1024*1024 # 100 Megabytes

  worker_processes 8
  worker_connections 32
  timeout 10

  listen "unix:/var/run/neocities/neocities.sock", :backlog => 2048

  pid "/var/run/neocities/neocities.pid"
  stderr_path "/var/log/neocities/neocities.log"
  stdout_path "/var/log/neocities/neocities.log"

  preload_app true
 
  before_fork do |server, worker|
    old_pid = "/var/run/neocities/neocities.pid.oldbin"
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
