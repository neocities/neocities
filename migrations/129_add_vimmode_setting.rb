Sequel.migration do
  up {
    DB.add_column :sites, :vimmode_enabled, :boolean, default: false
  }

  down {
    DB.add_column :sites, :vimmode_enabled
  }
end

