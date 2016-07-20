Sequel.migration do
  up {
    DB.add_column :sites, :banned_at, Time
  }

  down {
    DB.drop_column :sites, :banned_at
  }
end
