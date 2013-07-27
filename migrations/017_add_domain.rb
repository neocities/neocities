Sequel.migration do
  up {
    DB.add_column :sites, :domain, :text, default: nil
  }

  down {
    DB.drop_column :sites, :domain
  }
end