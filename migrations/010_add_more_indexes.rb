Sequel.migration do
  up {
    DB.add_index :sites, :created_at
    DB.add_index :sites, :hits
  }

  down {
    DB.drop_index :sites, :created_at
    DB.drop_index :sites, :hits
  }
end
