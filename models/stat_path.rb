class StatPath < Sequel::Model
  RETAINMENT_DAYS = 7

  many_to_one :site

  def self.prune!
    where{created_at < (RETAINMENT_DAYS-2).days.ago.to_date}.delete
  end

  def self.create_or_get(site_id, name)
    opts = {site_id: site_id, name: name}
    stat_path = where(opts).where{created_at > RETAINMENT_DAYS.days.ago}.first
    DB[table_name].lock('EXCLUSIVE') {
      stat_path = create opts.merge created_at: Date.today
    } if stat_path.nil?

    stat_path
  end
end
