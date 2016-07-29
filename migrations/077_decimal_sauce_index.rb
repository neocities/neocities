Sequel.migration do
  up {
    DB.add_index :sites, :score
  }

  down {
    DB.drop_index :sites, :score
  }
end
