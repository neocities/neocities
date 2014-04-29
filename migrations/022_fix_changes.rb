Sequel.migration do
  up {
    DB.rename_table :changes, :site_changes
  }

  down {
    DB.drop_column :site_changes, :changes
  }
end