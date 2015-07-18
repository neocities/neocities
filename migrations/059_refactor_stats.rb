Sequel.migration do
  up {
    DB.drop_table :stats
    DB.create_table! :stats do
      primary_key :id
      Integer     :site_id,      index: true
      Date        :created_at,   index: true
      Integer     :hits,         default: 0
      Integer     :views,        default: 0
      Integer     :comments,     default: 0
      Integer     :follows,      default: 0
      Integer     :site_updates, default: 0
    end

    DB.create_table! :stat_referrers do
      primary_key :id
      Integer     :stat_id, index: true
      String      :url
      Integer     :views, default: 0
    end

    DB.create_table! :stat_locations do
      primary_key :id
      Integer     :stat_id, index: true
      String      :country_code2
      String      :region_name
      String      :city_name
      Decimal     :latitude
      Decimal     :longitude
      Integer     :views, default: 0
    end

    DB.create_table! :stat_paths do
      primary_key :id
      Integer     :stat_id, index: true
      String      :name
      Integer     :views, default: 0
    end
  }

  down {
    DB.drop_table :stats
    DB.create_table! :stats do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :hits, default: 0
      Integer     :views, default: 0
      DateTime    :created_at, index: true
    end

    DB.drop_table :stat_referrers
    DB.drop_table :stat_locations
    DB.drop_table :stat_paths
  }
end
