Sequel.migration do
  up {
    DB.add_index :site_change_files, :site_change_id
    DB.add_index :site_change_files, :site_id
  }

  down {
    DB.drop_index :site_change_files, :site_change_id
    DB.drop_index :site_change_files, :site_id
  }
end
