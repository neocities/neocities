Sequel.migration do
  up {
    DB.drop_column :sites, :ssl_cert_intermediate
  }

  down {
    DB.add_column :sites, :ssl_cert_intermediate, :text
  }
end