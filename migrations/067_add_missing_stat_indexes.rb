Sequel.migration do
  up {
    DB['create index stat_referrers_hash_multi on stat_referrers (site_id, md5(url))'].first
    #DB.add_index :stat_locations, :site_id
    #DB.add_index :stat_paths,     :site_id
  }

  down {
    DB['drop index stat_referrers_hash_multi'].first
    #DB.drop_index :stat_locations, :site_id
    #DB.drop_index :stat_paths,     :site_id
  }
end
