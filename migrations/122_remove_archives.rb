Sequel.migration do
  up {
    DB.drop_table :archives
    DB.drop_column :sites, :ipfs_archiving_enabled
  }

  down {
    DB.create_table! :archives do
      Integer  :site_id, index: true
      String   :ipfs_hash
      DateTime :updated_at, index: true
      unique [:site_id, :ipfs_hash]
    end

    DB.add_column  :sites, :ipfs_archiving_enabled, :boolean, default: false
  }
end