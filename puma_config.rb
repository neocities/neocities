require 'facter'

threads 1, 1
environment 'production'
#daemonize
pidfile '/var/run/neocities/neocities.pid'
stdout_redirect '/var/log/neocities/neocities.log', '/var/log/neocities/neocities-errors.log', true
quiet
workers Facter.value('processors')['count']
worker_timeout 600
preload_app!
on_worker_boot { DB.disconnect }
bind 'unix:/var/run/neocities/neocities.sock?backlog=2048'
