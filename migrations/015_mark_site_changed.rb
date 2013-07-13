Sequel.migration do
  up {
    DB.add_column :sites, :site_changed, :boolean, default: false
    DB.add_index  :sites, :site_changed
  }

  down {
    DB.drop_column :sites, :site_changed
    DB.drop_index  :sites, :site_changed
  }
end