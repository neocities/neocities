Sequel.migration do
  up {
    DB.create_table! :site_files do
      Integer  :site_id, index: true
      String   :path
      Bigint   :size
      String   :sha1_hash
      Boolean  :is_directory, default: false
      DateTime :created_at
      DateTime :updated_at
    end
  }

  down {
    DB.drop_table :site_files
  }
end