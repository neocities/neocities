Sequel.migration do
  up {
    DB.create_table! :archives do
      Integer  :site_id, index: true
      String   :ipfs_hash
      DateTime :updated_at, index: true
      unique [:site_id, :ipfs_hash]
    end
  }

  down {
    DB.drop_table :archives
  }
end
