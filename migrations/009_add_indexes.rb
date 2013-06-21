Sequel.migration do
  up {
    DB.add_index :sites, [:hits, :created_at]
  }

  down {
    DB.drop_index :sites, [:hits, :created_at]
  }
end