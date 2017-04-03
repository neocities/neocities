Sequel.migration do
  up {
    DB.add_index :sites_tags, :site_id
  }

  down {
    DB.drop_index :sites_tags, :site_id
  }
end
