class SiteChange < Sequel::Model
  NEW_CHANGE_TIMEOUT = 3600 * 4 # 4 hours
  many_to_one :site
  one_to_one  :event
  one_to_one  :site_change
  one_to_many :site_change_files

  def site_change_filenames(limit=4)
    site_change_files[0..limit-1].collect {|f| f.filename}
  end

  def self.record(site, filename)
    site_change = filter(site_id: site.id).order(:created_at.desc).first

    if site_change.nil? || site_change.created_at+NEW_CHANGE_TIMEOUT < Time.now
      site_change = create site: site
      Event.create site_id: site.id, site_change_id: site_change.id
    end

    site_change_file = site_change.site_change_files_dataset.filter(filename: filename).first

    if !site_change_file
      site_change.add_site_change_file filename: filename
    end
  end
end
