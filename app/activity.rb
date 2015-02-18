get '/activity' do
  #expires 7200, :public, :must_revalidate if self.class.production? # 2 hours
  params[:activity] = 'global' # FIXME this is a bad hack
  @events = Event.global_dataset.all
  erb :'activity'
end
