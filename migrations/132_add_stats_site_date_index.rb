Sequel.migration do
  change do
    alter_table(:stats) { add_index [:site_id, :created_at], name: :stats_site_date_idx }
  end
end