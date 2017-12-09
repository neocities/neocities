Sequel.migration do
  up {
    DB.add_index :sites, :email
  }

  down {
    DB.drop_index :sites, :email
  }
end
