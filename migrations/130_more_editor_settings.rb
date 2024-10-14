Sequel.migration do
  up {
    DB.add_column :sites, :editor_help_tooltips, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :editor_help_tooltips
  }
end