# This migration detaches stat_referrers, stat_locations and stat_paths
# from stats. Instead of stat_id, we'll add a created_at timestamp and remove
# after 7 days for both free and supporter plans (for now).
Sequel.migration do
  up {
    [:stat_referrers, :stat_paths, :stat_locations].each do |stat_table|
      add_column stat_table, :site_id, :integer, index: true
    end
  }

  down {
    [:stat_referrers, :stat_paths, :stat_locations].each do |stat_table|
      drop_column stat_table, :site_id
    end
  }
end
