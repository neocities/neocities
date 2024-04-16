require 'facter'

#threads 1, 1
environment 'production'
#daemonize
pidfile '/var/run/neocities/neocities.pid'
stdout_redirect '/var/log/neocities/neocities.stdout.log', '/var/log/neocities/neocities.stderr.log', true
quiet
workers Facter.value('processors')['count']
#preload_app!
prune_bundler
#on_worker_boot { DB.disconnect }
bind 'unix:/var/run/neocities/neocities.sock?backlog=2048'
supported_http_methods Puma::Const::IANA_HTTP_METHODS
