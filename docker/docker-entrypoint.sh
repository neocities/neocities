#!/bin/bash
set -e

# Ensure gitignored directories and required seed files exist.
# Needed when the project is volume-mounted from the host.
mkdir -p public/sites public/site_thumbnails public/site_screenshots \
         public/banned_sites public/deleted_sites

touch files/disposable_email_blacklist.conf \
      files/disposable_email_whitelist.conf

case "$1" in
  web)
    exec bundle exec rackup -o 0.0.0.0 -p 9292
    ;;
  worker)
    exec bundle exec sidekiq -r ./environment.rb
    ;;
  *)
    exec "$@"
    ;;
esac
