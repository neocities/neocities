Sequel.migration do
  up {
    DB.rename_table :changes, :site_changes
  }

  down {
    DB.rename_table :site_changes, :changes
  }
end