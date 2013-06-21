Sequel.migration do
  up {
    DB.drop_column :sites, :initial_index_changed
  }

  down {
    DB.add_column :sites, :initial_index_changed, :boolean, default: false
  }
end