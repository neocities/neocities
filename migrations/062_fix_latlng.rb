Sequel.migration do
  up {
    drop_column :stat_locations, :latitude
    drop_column :stat_locations, :longitude
    add_column  :stat_locations, :latitude, :float
    add_column  :stat_locations, :longitude, :float
  }

  down {
    # meh.
  }
end
