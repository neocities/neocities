Sequel.migration do
  up {
    DB.create_table! :tags do
      primary_key :id
      String      :name
      DateTime    :created_at
    end
  }

  down {
    DB.drop_table :tags
  }
end