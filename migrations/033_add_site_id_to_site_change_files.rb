Sequel.migration do
  up {
    DB.add_column :site_change_files, :site_id, :integer
  }

  down {
    DB.drop_column :site_change_files, :site_id
  }
end
