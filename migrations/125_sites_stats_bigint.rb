Sequel.migration do
  up {
    alter_table(:sites) do
      set_column_type :hits, :bigint
      set_column_type :views, :bigint
    end
  }

  down {
    alter_table(:sites) do
      set_column_type :hits, Integer
      set_column_type :views, Integer
    end
  }
end
