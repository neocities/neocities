get '/activity' do
  expires 7200, :public, :must_revalidate if self.class.production? # 2 hours

  @page = params[:page] || 1
  @pagination_dataset = Event.global_dataset.paginate(@page.to_i, Event::GLOBAL_PAGINATION_LENGTH)
  @events = @pagination_dataset.all

  erb :'activity'
end
