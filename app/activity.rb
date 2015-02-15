get '/activity' do
  expires 14400, :public, :must_revalidate if self.class.production? # 4 hours
  params[:activity] = 'global' # FIXME this is a bad hack
  @events = Event.global_dataset.all
  erb :'activity'
end
