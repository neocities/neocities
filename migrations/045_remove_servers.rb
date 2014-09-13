Sequel.migration do
  up {
    DB.drop_table :servers
  }

  down {
    DB.create_table! :servers do
      primary_key :id
      String      :ip
      Integer     :slots_available
      DateTime    :created_at
      DateTime    :updated_at
    end
  }
end