# frozen_string_literal: true
require 'geoip'

class StatLocation < Sequel::Model
  GEOCITY_PATH = './files/GeoLiteCity.dat'
  RETAINMENT_DAYS = 7

  many_to_one :site

  def self.prune!
    where{created_at < (RETAINMENT_DAYS-2).days.ago.to_date}.delete
  end

  def self.create_or_get(site_id, ip)
    geoip = GeoIP.new GEOCITY_PATH
    city = geoip.city ip

    return nil if city.nil?

    opts = {site_id: site_id, country_code2: city.country_code2, region_name: city.region_name, city_name: city.city_name}
    stat_location = where(opts).where{created_at > RETAINMENT_DAYS.days.ago}.first
    DB[table_name].lock('EXCLUSIVE') {
      stat_location = create opts.merge(latitude: city.latitude, longitude: city.longitude, created_at: Date.today)
    } if stat_location.nil?

    stat_location
  end
end
