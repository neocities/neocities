Sequel.migration do
  up {
    DB.add_column :sites, :ssl_cert_intermediate, :text
  }

  down {
    DB.drop_column :sites, :ssl_cert_intermediate
  }
end