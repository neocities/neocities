Sequel.migration do
  up {
    alter_table(:daily_site_stats) do
      set_column_type :hits, :bigint
      set_column_type :views, :bigint
      set_column_type :bandwidth, :bigint
      set_column_type :site_updates, :bigint
    end
  }

  down {
    alter_table(:daily_site_stats) do
      set_column_type :hits, Integer
      set_column_type :views, Integer
      set_column_type :bandwidth, Integer
      set_column_type :site_updates, Integer
    end
  }
end
