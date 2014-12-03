require 'zlib'
require 'rubygems/package'

get '/sysops/proxy/map.txt' do
  require_proxy_auth
  domains = ''
  Site.exclude(domain: nil).
       exclude(domain: '').
       select(:username,:domain).
       all.
       collect do |s|
    domains << "#{s.domain} #{s.username};\n"
  end
  content_type :text
  domains
end

get '/sysops/proxy/sslcerts.tar.gz' do
  require_proxy_auth
  sites = Site.ssl_sites

  nginx_config = ''

  tar = StringIO.new

  Gem::Package::TarWriter.new(tar) do |writer|
    writer.mkdir 'sslcerts', 0740
    writer.mkdir 'sslcerts/certs', 0740

    sites.each do |site|
      writer.add_file "sslcerts/certs/#{site.username}.key", 0640 do |f|
        f.write site.ssl_key
      end

      writer.add_file "sslcerts/certs/#{site.username}.crt", 0640 do |f|
        f.write site.ssl_cert
      end

      nginx_config << %{
        server {
          listen 443 ssl;
          server_name #{site.domain} *.#{site.domain};
          ssl_certificate sslsites/certs/#{site.username}.crt;
          ssl_certificate_key sslsites/certs/#{site.username}.key;

          location / {
            proxy_http_version 1.1;
            proxy_set_header Host #{site.username}.neocities.org;
            proxy_pass http://127.0.0.1$request_uri;
          }
        }
      }.unindent
    end

    writer.add_file "sslcerts/sslsites.conf", 0640 do |f|
      f.write nginx_config
    end
  end

  tar.rewind

  package = StringIO.new 'b'
  package.set_encoding 'binary'
  gzip = Zlib::GzipWriter.new package
  gzip.write tar.read
  tar.close
  gzip.finish
  package.rewind

  attachment
  package.read
end

class ProxyAccessViolation < StandardError; end

def require_proxy_auth
  begin
    auth = request.env['HTTP_AUTHORIZATION']
    user, pass = Base64.decode64(auth.match(/Basic (.+)/)[1]).split(':')
    raise ProxyAccessViolation unless pass == $config['proxy_pass']
  rescue
    raise ProxyAccessViolation, "Violator: #{request.ip}" unless pass == $config['proxy_pass']
  end
end