Sequel.migration do
  up {
    DB.add_index :events, [:created_at, :site_id, :site_change_id, :is_deleted], name: :events_rss_index, order: {created_at: :desc}
  }

  down {
    DB.drop_index :events, :rss
  }
end