Sequel.migration do
  up {
    DB.add_column :sites, :ssl_key, :text
    DB.add_column :sites, :ssl_cert, :text
    
  }

  down {
    DB.drop_column :sites, :ssl_key
    DB.drop_column :sites, :ssl_cert
  }
end
