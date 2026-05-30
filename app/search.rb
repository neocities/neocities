# frozen_string_literal: true

post '/search/?' do
  query = params[:q].to_s.strip
  redirect query.blank? ? '/search' : "/search?#{Rack::Utils.build_query(q: query)}"
end

get '/search/?' do
  @query = params[:q].to_s.strip
  @title = @query.blank? ? 'Neocities Search' : 'Site Search'
  @description = 'Search websites hosted on Neocities.'

  if !@query.blank?
    @start = params[:start].to_i
    @start = 0 if @start < 0

    @resp = JSON.parse HTTP.get('https://search.neocitiesops.net/customsearch/v1', params: {
      num: 100,
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
        item['username'] = username if site.profile_enabled

        screenshot_path = unencoded_path

        screenshot_path << 'index' if screenshot_path[-1] == '/'

        if ENV['RACK_ENV'] == 'development'
          screenshot_path += '.html'
        else
          ['.html', '.htm'].each do |ext|
            if site.screenshot_exists?(screenshot_path + ext, '540x405')
              screenshot_path += ext
              break
            end
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
