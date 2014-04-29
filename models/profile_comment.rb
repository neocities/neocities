class ProfileComment < Sequel::Model
  one_to_one :event
  many_to_one :site
  many_to_one :actioning_site, :class => :Site

  def after_create
    self.event = Event.create site_id: site.id
  end
end