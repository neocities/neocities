get '/browse/?' do
  @current_page = params[:current_page]
  @current_page = @current_page.to_i
  @current_page = 1 if @current_page == 0

  params.delete 'tag' if params[:tag].nil? || params[:tag].strip.empty?

  if is_education?
    site_dataset = education_sites_dataset
  else
    site_dataset = browse_sites_dataset
  end

  site_dataset = site_dataset.paginate @current_page, Site::BROWSE_PAGINATION_LENGTH
  @page_count = site_dataset.page_count || 1
  @sites = site_dataset.all
  if params[:tag]
    @title = "Sites tagged #{params[:tag]}"
  end
  erb :browse
end

def education_sites_dataset
  site_dataset = Site.filter is_deleted: false
  site_dataset = site_dataset.association_join(:tags).select_all(:sites)
  params[:tag] = current_site.tags.first.name
  site_dataset.where! ['tags.name = ?', params[:tag]]
end

def browse_sites_dataset
  site_dataset = Site.filter(is_deleted: false, is_banned: false, is_crashing: false).filter(site_changed: true)

  if current_site
    if !current_site.blocking_site_ids.empty?
      site_dataset.where!(Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocking_site_ids))
    end

    if current_site.blocks_dataset.count
      site_dataset.where!(
        Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocks_dataset.select(:actioning_site_id).all.collect {|s| s.actioning_site_id})
      )
    end
  end

  case params[:sort_by]
    when 'featured'
      site_dataset.exclude! featured_at: nil
      site_dataset.order! :featured_at.desc
    when 'hits'
      site_dataset.where!{views > 100}
      site_dataset.order!(:hits.desc, :site_updated_at.desc)
    when 'views'
      site_dataset.where!{views > 100}
      site_dataset.order!(:views.desc, :site_updated_at.desc)
    when 'newest'
      site_dataset.order!(:created_at.desc, :views.desc)
    when 'oldest'
      site_dataset.where!{views > 100}
      site_dataset.order!(:created_at, :views.desc)
    when 'random'
      site_dataset.where!{views > 100}
      site_dataset.where! 'random() < 0.01'
    when 'last_updated'
      site_dataset.where!{views > 100}
      params[:sort_by] = 'last_updated'
      site_dataset.order!(:site_updated_at.desc, :views.desc)
    else
      if params[:tag]
        params[:sort_by] = 'views'
        site_dataset.order!(:views.desc, :site_updated_at.desc)
      else
        params[:sort_by] = 'last_updated'
        site_dataset.where!{views > 100}
        site_dataset.order!(:site_updated_at.desc, :views.desc)
      end
  end

  site_dataset.where! ['sites.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]

  if params[:tag]
    site_dataset = site_dataset.association_join(:tags).select_all(:sites)
    site_dataset.where! ['tags.name = ?', params[:tag]]
    site_dataset.where! ['tags.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]
  end

  site_dataset
end
