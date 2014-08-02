Sequel.migration do
  up {
    DB.add_column :sites, :editor_theme, :text
  }

  down {
    DB.drop_column :sites, :editor_theme
  }
end