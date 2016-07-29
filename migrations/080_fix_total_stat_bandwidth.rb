Sequel.migration do
  up {
    DB.drop_column :daily_site_stats, :bandwidth
    DB.add_column :daily_site_stats, :bandwidth, :integer, default: 0
  }

  down {
    DB.drop_column :daily_site_stats, :bandwidth
    DB.add_column :daily_site_stats, :bandwidth, :integer
  }
end
