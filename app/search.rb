# frozen_string_literal: true

SEARCH_BACKEND_URL = $config['search_backend_url']
SEARCH_BACKEND_TIMEOUT = $config['search_backend_timeout']

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

    @items = []
    @total_results = 0

    begin
      @resp = JSON.parse HTTP.timeout(global: SEARCH_BACKEND_TIMEOUT).get(SEARCH_BACKEND_URL, params: {
        num: 100,
        start: @start,
        q: Rack::Utils.escape(@query) + ' -filetype:pdf -filetype:txt site:*.neocities.org'
      }).to_s
    rescue HTTP::Error, JSON::ParserError
      @resp = {}
    end

    if @resp.is_a?(Hash) && @resp['error'].nil? && @resp.dig('searchInformation', 'totalResults').to_i != 0
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
          screenshot_found = true
        else
          ['.html', '.htm'].each do |ext|
            if site.screenshot_exists?(screenshot_path + ext, '540x405')
              screenshot_path += ext
              screenshot_found = true
              break
            end
          end
        end

        item['screenshot_url'] = site.screenshot_url(screenshot_path, '540x405')
        @items << item if screenshot_found
      end
    end
  else
    @items = nil
    @total_results = 0
  end

  erb :'search'
end
