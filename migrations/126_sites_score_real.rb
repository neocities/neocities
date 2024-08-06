Sequel.migration do
    up {
      alter_table(:sites) do
        set_column_type :score, :real
      end
    }
  
    down {
      alter_table(:sites) do
        set_column_type :score, :decimal
      end
    }
  end