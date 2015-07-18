Sequel.migration do
  up {
    DB.add_index :stat_referrers, :site_id
  }

  down {
    DB.drop_index :stat_referrers, :site_id
  }
end
