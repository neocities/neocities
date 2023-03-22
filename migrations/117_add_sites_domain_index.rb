Sequel.migration do
    up {
      DB.add_index :sites, :domain
    }

    down {
      DB.drop_index :sites, :domain
    }
  end
