Sequel.migration do
  up {
    DB.add_index :sites, :username
  }

  down {
    DB.drop_index :sites, :username
  }
end
