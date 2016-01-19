Sequel.migration do
  up {
    DB.add_column :daily_site_stats, :bandwidth, :integer
  }

  down {
    DB.drop_column :daily_site_stats, :bandwidth
  }
end
