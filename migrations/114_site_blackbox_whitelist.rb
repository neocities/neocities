Sequel.migration do
  up {
    DB.add_column :sites, :blackbox_whitelisted, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :blackbox_whitelisted
  }
end
