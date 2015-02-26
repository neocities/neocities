get '/activity' do
  #expires 7200, :public, :must_revalidate if self.class.production? # 2 hours
  params[:activity] = 'global' # FIXME this is a bad hack

  global_dataset = Event.global_dataset

  if params[:event_id]
    global_dataset.where! Sequel.qualify(:events, :id) => params[:event_id]
  end

  @events = global_dataset.all

  erb :'activity'
end
