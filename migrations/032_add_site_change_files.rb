Sequel.migration do
  up {
    DB.create_table! :site_change_files do
      primary_key :id
      Integer  :site_change_id
      String   :filename
      DateTime :created_at
    end
  }

  down {
    DB.drop_table :site_change_files
  }
end
