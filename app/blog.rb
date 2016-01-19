get '/blog/?' do
  redirect 'https://blog.neocities.org', 301
end

get '/blog/:article' do |article|
  redirect "https://blog.neocities.org/#{article}.html", 301
end
