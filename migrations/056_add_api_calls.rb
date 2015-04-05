Sequel.migration do
  up {
    DB.add_column :sites, :api_calls, Integer, default: 0, index: true
  }

  down {
    DB.drop_column :sites, :api_calls
  }
end
