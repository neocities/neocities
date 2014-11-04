Sequel.migration do
  up {
    DB.drop_table :site_files

    DB.create_table! :site_files do
      Integer  :site_id
      String   :path
      Bigint   :size
      String   :sha1_hash
      Boolean  :is_directory, default: false
      DateTime :created_at
      DateTime :updated_at
      primary_key [:site_id, :path], :name => :site_files_pk
    end
  }

  down {
    DB.drop_table :site_files

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
end