Sequel.migration do
  up {
    DB.add_column :sites, :cert_updated_at, Time
  }

  down {
    DB.drop_column :sites, :cert_updated_at
  }
end
