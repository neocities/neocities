# frozen_string_literal: true

def daily_search_max?
  query_count = $redis_cache.get('search_query_count').to_i
  query_count >= $config['google_custom_search_query_limit']
end

post '/search/?' do
  query = params[:q].to_s.strip
  redirect query.blank? ? '/search' : "/search?#{Rack::Utils.build_query(q: query)}"
end

get '/search/?' do
  @query = params[:q].to_s.strip
  @title = @query.blank? ? 'Neocities Search' : 'Site Search'
  @description = 'Search websites hosted on Neocities.'

  @daily_search_max_reached = daily_search_max?

  if @daily_search_max_reached
    @items = nil
    @total_results = 0
  elsif !@query.blank?
    created = $redis_cache.set('search_query_count', 1, nx: true, ex: 86400)
    $redis_cache.incr('search_query_count') unless created

    @start = params[:start].to_i
    @start = 0 if @start < 0

    @resp = JSON.parse HTTP.get('https://www.googleapis.com/customsearch/v1', params: {
      key: $config['google_custom_search_key'],
      cx: $config['google_custom_search_cx'],
      safe: 'active',
      start: @start,
      q: Rack::Utils.escape(@query) + ' -filetype:pdf -filetype:txt site:*.neocities.org'
    })

    @items = []

    if @total_results != 0 && @resp['error'].nil? && @resp['searchInformation']['totalResults'] != "0"
      @total_results = @resp['searchInformation']['totalResults'].to_i
      @resp['items'].each do |item|
        link = Addressable::URI.parse(item['link'])
        path = link.path || '/'
        unencoded_path = begin
          Rack::Utils.unescape(Rack::Utils.unescape(path)) # Yes, it needs to be decoded twice
        rescue ArgumentError
          path # Fall back when the path includes invalid %-encoding
        end
        item['unencoded_link'] = unencoded_path == '/' ? link.host : link.host+unencoded_path
        item['link'] = link

        next if link.host == 'neocities.org'

        username = link.host.split('.').first
        site = Site[username: username]
        next if site.nil? || site.is_deleted || site.is_nsfw

        screenshot_path = unencoded_path

        screenshot_path << 'index' if screenshot_path[-1] == '/'

        ['.html', '.htm'].each do |ext|
          if site.screenshot_exists?(screenshot_path + ext, '540x405')
            screenshot_path += ext
            break
          end
        end

        item['screenshot_url'] = site.screenshot_url(screenshot_path, '540x405')
        @items << item
      end
    end
  else
    @items = nil
    @total_results = 0
  end

  erb :'search'
end
