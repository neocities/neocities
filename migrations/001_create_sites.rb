Sequel.migration do
  up {
    DB.create_table! :sites do
      String   :username, primary_key: true
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