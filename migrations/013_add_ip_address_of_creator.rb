Sequel.migration do
  up {
    DB.add_column :sites, :ip, :text
  }

  down {
    DB.drop_column :sites, :ip
  }
end