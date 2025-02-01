# frozen_string_literal: true
class SiteChange < Sequel::Model
  NEW_CHANGE_TIMEOUT = 3600 * 24 # 24 hours
  many_to_one :site
  one_to_one  :event
  one_to_one  :site_change
  one_to_many :site_change_files

  def site_change_filenames(limit=6)
    filenames = site_change_files_dataset.select(:filename).limit(limit).order(:created_at.desc).all.collect {|f| f.filename}
    filenames = filenames.reject { |f| site.should_ignore_from_feed?(f) }
    filenames.sort_by {|f| f.match('html') ? 0 : 1}
  end

  def self.record(site, filename)
    return if site.should_ignore_from_feed?(filename)

    site_change = filter(site_id: site.id).order(:created_at.desc).first

    if site_change.nil? || site_change.created_at+NEW_CHANGE_TIMEOUT < Time.now
      site_change = create site: site
      Event.create site_id: site.id, site_change_id: site_change.id
    end

    site_change_file = site_change.site_change_files_dataset.filter(filename: filename).first

    if !site_change_file
      site_change.add_site_change_file site_id: site.id, filename: filename
    end
  end
end
