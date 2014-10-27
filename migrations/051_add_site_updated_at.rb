Sequel.migration do
  up {
    DB.add_column :sites, :site_updated_at, DateTime, index: true
  }

  down {
    DB.drop_column :sites, :site_updated_at
  }
end