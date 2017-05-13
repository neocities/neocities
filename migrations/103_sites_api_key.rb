Sequel.migration do
  up {
    DB.add_column :sites, :api_key, :text
  }

  down {
    DB.drop_column :sites, :api_key
  }
end
