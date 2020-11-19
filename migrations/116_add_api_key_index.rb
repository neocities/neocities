Sequel.migration do
    up {
      DB.add_index :sites, :api_key
    }
  
    down {
      DB.drop_index :sites, :api_key
    }
  end