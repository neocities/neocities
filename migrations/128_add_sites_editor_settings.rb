Sequel.migration do
  up {
    DB.add_column :sites, :autocomplete_enabled, :boolean, default: false
    DB.add_column :sites, :editor_font_size, :int, default: 14
  }

  down {
    DB.add_column :sites, :autocomplete_enabled
    DB.add_column :sites, :editor_font_size
  }
end

