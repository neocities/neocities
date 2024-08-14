Sequel.migration do
  up {
    alter_table(:tags) do
      add_unique_constraint :name
    end   
  }
  
  down {
    alter_table(:tags) do
      drop_constraint :tags_name_key
    end   
  }
end