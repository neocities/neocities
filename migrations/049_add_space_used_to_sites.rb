Sequel.migration do
  up {
    DB.add_column :sites, :space_used, :bigint, default: 0, index: true
  }

  down {
    DB.drop_column :sites, :space_used
  }
end