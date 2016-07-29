Sequel.migration do
  up {
    DB.create_table! :daily_site_stats do
      primary_key :id
      Date        :created_at,   index: true
      Integer     :hits,         default: 0
      Integer     :views,        default: 0
      Integer     :comments,     default: 0
      Integer     :follows,      default: 0
      Integer     :site_updates, default: 0
    end
  }

  down {
    DB.drop_table :daily_site_stats
  }
end
