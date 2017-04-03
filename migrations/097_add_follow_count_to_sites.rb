Sequel.migration do
  up {
    DB.add_column :sites, :follow_count, :integer, default: 0
  }

  down {
    DB.drop_column :sites, :follow_count
  }
end
