Sequel.migration do
    up {
      DB.rename_column :sites, :autocomplete_enabled, :editor_autocomplete_enabled
      DB.rename_column :sites, :keyboard_mode,        :editor_keyboard_mode
      DB.rename_column :sites, :tab_width,            :editor_tab_width
      DB.drop_column :sites, :editor_keyboard_mode
      DB.add_column :sites, :editor_keyboard_mode, String, size: 10
    }
  
    down {
      DB.rename_column :sites, :editor_autocomplete_enabled, :autocomplete_enabled
      DB.rename_column :sites, :editor_tab_width,            :tab_width
      DB.drop_column :sites, :editor_keyboard_mode
      DB.add_column :sites, :keyboard_mode, :int, default: 0
    }
  end