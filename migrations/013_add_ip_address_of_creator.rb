Sequel.migration do
  up {
    DB.add_column :sites, :ip, :text
  }

  down {
    DB.add_column :sites, :ip
  }
end