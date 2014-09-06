Sequel.migration do
  up {
    DB.add_column :sites, :commenting_allowed, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :commenting_allowed
  }
end