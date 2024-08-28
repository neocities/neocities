get '/activity' do
  #expires 7200, :public, :must_revalidate if self.class.production? # 2 hours

  @page = params[:page] || 1

  @pagination_dataset = Event.global_dataset

  if current_site
    blocking_site_ids = current_site.blocking_site_ids
    @pagination_dataset.exclude(events__site_id: blocking_site_ids).exclude(events__actioning_site_id: blocking_site_ids)
  end

  @pagination_dataset = @pagination_dataset.paginate @page.to_i, Event::GLOBAL_PAGINATION_LENGTH
  @events = @pagination_dataset.all

  erb :'activity'
end
