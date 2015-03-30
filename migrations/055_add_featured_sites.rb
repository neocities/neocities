Sequel.migration do
  up {
    DB.add_column :sites, :featured_at, DateTime, index: true
  }

  down {
    DB.drop_column :sites, :featured_at
  }
end
