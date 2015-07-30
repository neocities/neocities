Sequel.migration do
  up {
    DB.add_column :sites, :commenting_banned, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :commenting_banned
  }
end
