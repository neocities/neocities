require 'net/http'
require 'uri'

get '/blog/?' do
  expires 500, :public, :must_revalidate
  return Net::HTTP.get_response(URI('http://blog.neocities.org')).body
end

get '/blog/:article' do |article|
  expires 500, :public, :must_revalidate

  attempted = false

  begin
    return Net::HTTP.get_response(URI("http://blog.neocities.org/#{article}.html")).body
  rescue => e
    raise e if attempted
    attempted = true
    article = article.match(/^[a-zA-Z0-9-]+/).to_s
    retry
  end
end
