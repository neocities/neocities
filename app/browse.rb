get '/browse/?' do
  @surfmode = false
  @page = params[:page].to_i
  @page = 1 if @page == 0

  params.delete 'tag' if params[:tag].nil? || params[:tag].strip.empty?

  if is_education?
    site_dataset = education_sites_dataset
  else
    site_dataset = browse_sites_dataset
  end

  site_dataset = site_dataset.paginate @page, Site::BROWSE_PAGINATION_LENGTH
  @pagination_dataset = site_dataset
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

  site_dataset = Site.browse_dataset

  if current_site
    site_dataset.or! sites__id: current_site.id

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
    when 'special_sauce'
      site_dataset.exclude! score: nil
      site_dataset.order! :score.desc
    when 'followers'
      site_dataset.order! :follow_count.desc, :updated_at.desc
    when 'supporters'
      site_dataset.exclude! plan_type: nil
      site_dataset.exclude! plan_type: 'free'
      site_dataset.order! :views.desc, :site_updated_at.desc
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
      site_dataset.exclude!(site_updated_at: nil)
      site_dataset.order!(:site_updated_at.desc, :views.desc)
    when 'tipping_enabled'
      site_dataset.where! tipping_enabled: true
      site_dataset.where!("(tipping_paypal is not null and tipping_paypal != '') or (tipping_bitcoin is not null and tipping_bitcoin != '')")
      site_dataset.where!{views > 10_000}
      site_dataset.group! :sites__id
      site_dataset.order! :follow_count.desc, :views.desc, :updated_at.desc
    else
      params[:sort_by] = 'followers'
      site_dataset.select_all! :sites
      site_dataset.order! :follow_count.desc, :views.desc, :updated_at.desc
  end

  site_dataset.where! ['sites.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]

  if params[:tag]
    site_dataset.inner_join! :sites_tags, :site_id => :id
    site_dataset.inner_join! :tags, :id => :sites_tags__tag_id
    site_dataset.where! ['tags.name = ?', params[:tag]]
    site_dataset.where! ['tags.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]
  end

  site_dataset
end
