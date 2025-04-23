def processor_count
  case RbConfig::CONFIG['host_os']
  when /darwin9/
    `hwprefs cpu_count`.to_i
  when /darwin/
    ((`which hwprefs` != '') ? `hwprefs thread_count` : `sysctl -n hw.ncpu`).to_i
  when /linux/
    `cat /proc/cpuinfo | grep processor | wc -l`.to_i
  when /freebsd/
    `sysctl -n hw.ncpu`.to_i
  when /mswin|mingw/
    require 'win32ole'
    wmi = WIN32OLE.connect("winmgmts://")
    cpu = wmi.ExecQuery("select NumberOfCores from Win32_Processor") # TODO count hyper-threaded in this
    cpu.to_enum.first.NumberOfCores
  end
end

Rainbows! do
  use :ThreadPool

  client_max_body_size 100*1024*1024 # 100 Megabytes

  worker_processes processor_count
  worker_connections 32
  timeout 600 # 10 minutes

  listen "unix:/var/run/neocities/neocities.sock", :backlog => 2048

  pid "/var/run/neocities/neocities.pid"
  stderr_path "/var/log/neocities/neocities.log"
  stdout_path "/var/log/neocities/neocities.log"

  preload_app true

  before_fork do |server, worker|
    old_pid = "/var/run/neocities/neocities.pid.oldbin"
    if File.exist?(old_pid) && server.pid != old_pid
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
