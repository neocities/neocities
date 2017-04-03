Sequel.migration do
  up {
    DB.add_index :sites, :follow_count
  }

  down {
    DB.drop_index :sites, :follow_count
  }
end
