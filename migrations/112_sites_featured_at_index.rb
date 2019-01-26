Sequel.migration do
  up {
    DB.add_index :sites, :featured_at
  }

  down {
    DB.drop_index :sites, :featured_at
  }
end
