raise 'nope'

Sequel.migration do
  up {
    raise 'derp'
    DB.drop_table :stats
    DB.drop_table :stat_referrers
    DB.drop_table :stat_paths
    DB.drop_table :stat_locations

    DB.create_table! :hits do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :hit_referrer_id
      Integer     :hit_path_id
      Integer     :hit_location_id
      Bignum      :bandwidth
      Time        :accessed_at, index: true
    end

    DB.create_table! :hit_referrers do
      primary_key :id
      String      :uri, index: {unique: true}
    end

    DB.create_table! :hit_locations do
      primary_key :id
      String      :country_code2
      String      :region_name
      String      :city_name
      Float       :latitude
      Float       :longitude
    end

    DB.create_table! :hit_paths do
      primary_key :id
      String      :path, index: {unique: true}
    end
  }

  down {
    raise 'No.' if ENV['RACK_ENV'] == 'production'

    %i{hits hit_referrers hit_locations hit_paths}.each do |t|
      DB.drop_table t
    end

    DB.create_table! :stats do
      primary_key :id
      Integer :site_id
      Date :created_at
      Integer :hits
      Integer :views
      Integer :comments
      Integer :follows
      Integer :site_updates
    end

    DB.create_table! :stat_referrers do
      primary_key :id
      Integer :stat_id
      String :url
      String :views
    end

    DB.create_table! :stat_locations do
      primary_key :id
      Integer :stat_id
      String :country_code2
      String :region_name
      String :city_name
      Decimal :latitude
      Decimal :longitude
      Integer :views
    end

    DB.create_table :stat_paths do
      primary_key :id
      Integer     :stat_id
      String      :name
      Integer     :views
    end
  }
end

