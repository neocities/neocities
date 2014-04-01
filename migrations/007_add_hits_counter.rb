Sequel.migration do
  up {
    DB.add_column :sites, :hits, :integer, default: 0
  }

  down {
    DB.drop_column :sites, :hits
  }
end