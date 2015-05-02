class StatPath < Sequel::Model
  RETAINMENT_PERIOD = 7.days

  many_to_one :site

  def self.create_or_get(site_id, name)
    opts = {site_id: site_id, name: name}
    stat_path = where(opts).where{created_at > RETAINMENT_PERIOD.ago}.first
    DB[table_name].lock('EXCLUSIVE') {
      stat_path = create opts.merge created_at: Date.today
    } if stat_path.nil?

    stat_path
  end
end
