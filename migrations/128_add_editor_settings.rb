Sequel.migration do
  up {
    DB.add_column :sites, :autocomplete_enabled, :boolean, default: false
    DB.add_column :sites, :editor_font_size, :int, default: 14
    DB.add_column :sites, :keyboard_mode, :int, default: 0
    DB.add_column :sites, :tab_width, :int, default: 2
  }

  down {
    DB.drop_column :sites, :autocomplete_enabled
    DB.drop_column :sites, :editor_font_size
    DB.drop_column :sites, :keyboard_mode
    DB.drop_column :sites, :tab_width
  }
end