Sequel.migration do
  up {
    DB.drop_column :sites, :archiving_disabled
    DB.drop_column :sites, :archiving_private
    DB.add_column  :sites, :ipfs_archiving_enabled, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :ipfs_archiving_enabled
    DB.add_column  :sites, :archiving_disabled, :boolean, default: false
    DB.add_column  :sites, :archiving_private,  :boolean, default: false
  }
end
