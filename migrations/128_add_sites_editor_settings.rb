Sequel.migration do
  up {
    DB.add_column :sites, :autocomplete_enabled, :boolean, default: false
    DB.add_column :sites, :vimmode_enabled, :boolean, default: false
  }

  down {
    DB.add_column :sites, :autocomplete_enabled
    DB.add_column :sites, :vimmode_enabled
  }
end

