get '/surf/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].strip.empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, 1
  @page_count = site_dataset.page_count || 1
  @site = site_dataset.first
  redirect "/browse?#{Rack::Utils.build_query params}" if @site.nil?
  erb :'surf', layout: false
end

get '/surf/:username' do |username|
  @site = Site.select(:id, :username, :title, :domain, :views, :stripe_customer_id).where(username: username).first
  not_found if @site.nil?
  @title = @site.title
  not_found if @site.nil?
  erb :'surf', layout: false
end

get %r{\/surf\/proxy\/([\w-]+)\/(.+)|\/surf\/proxy\/([\w-]+)\/?} do
  captures = params[:captures].compact
  username = captures.first
  path = captures.length == 2 ? captures.last : ''

  site = Site.where(username: username).select(:id, :username, :title, :domain).first
  not_found if site.nil?

  resp = RestClient.get "http://#{site.username}.neocities.org/#{path}"

  content_type resp.headers[:content_type]
  site_body = resp.body

  unless path == '/' || path == '' || path.match(/\.html?$/i)
    return site_body
  end

  attributes = ['src', 'href', 'background']

  new_site_body = site_body.dup

  site_body.gsub(/(?<name>\b\w+\b)\s*=\s*(?<value>"[^"]*"|'[^']*'|[^"'<>\s]+)/i) do |ele|
    attributes.each do |attr|
      if ele.match attr
        uri = ele.match(/\"(.+)\"|\'(.+)\'/).captures.first

        new_ele = nil

        if uri.match /^\//
          new_ele = ele.gsub(uri, "#{$config['surf_proxy_uri']}/surf/proxy/#{site.username}#{uri}")
        elsif !uri.match /^\w+:\/\//
          new_ele = ele.gsub(uri, "#{$config['surf_proxy_uri']}/surf/proxy/#{site.username}/#{uri}")
        end

        new_site_body.gsub! ele, new_ele if new_ele
      end
    end
  end

  new_site_body
end
