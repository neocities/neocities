Sequel.migration do
  up {
    DB.rename_column :events, :site_update_id, :site_change_id
  }

  down {
    DB.rename_column :events, :site_change_id, :site_update_id
  }
end
