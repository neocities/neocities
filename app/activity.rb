get '/activity' do
  #expires 7200, :public, :must_revalidate if self.class.production? # 2 hours
  params[:activity] = 'global' # FIXME this is a bad hack

  global_dataset = Event.global_dataset

  if params[:event_id]
    global_dataset.where! Sequel.qualify(:events, :id) => params[:event_id]
  end

  events = global_dataset.all
  site_change_events = Event.global_site_changes_dataset.limit(100).all

  @events = []

  events.each do |event|
    unless site_change_events.empty?
      until site_change_events.first.created_at < event.created_at
        @events << site_change_events.shift
        break if site_change_events.empty?
      end
    end
    @events << event
  end

  erb :'activity'
end
