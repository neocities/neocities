Sequel.migration do
  up {
    DB.add_index :sites, [:follow_count, :updated_at, :views]
  }

  down {
    DB.drop_index :sites, [:follow_count, :updated_at, :views]
  }
end
