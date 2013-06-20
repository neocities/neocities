Sequel.migration do
  up {
    DB.add_column :sites, :initial_index_changed, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :initial_index_changed
  }
end