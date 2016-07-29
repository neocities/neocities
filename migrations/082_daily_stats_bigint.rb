Sequel.migration do
  up {
    alter_table(:daily_site_stats) do
      set_column_type :hits, Bignum
      set_column_type :views, Bignum
      set_column_type :bandwidth, Bignum
      set_column_type :site_updates, Bignum
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
