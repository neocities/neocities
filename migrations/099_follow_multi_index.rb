Sequel.migration do
  up {
    DB.add_index :sites, [:follow_count, :views, :updated_at]
  }

  down {
    DB.drop_index :sites, [:follow_count, :views, :updated_at]
  }
end
