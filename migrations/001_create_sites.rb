Sequel.migration do
  up {
    DB.create_table! :sites do
      primary_key :id
      String   :username
      String   :email
      String   :password
      Integer  :server_id
      DateTime :created_at
      DateTime :updated_at
    end
  }

  down {
    DB.drop_table :sites
  }
end