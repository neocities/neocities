Sequel.migration do
  up {
    DB.add_column :sites, :changed_count, :integer, default: 0
    DB.add_index  :sites, :changed_count
  }

  down {
    DB.drop_column :sites, :changed_count
    DB.drop_index  :sites, :changed_count
  }
end