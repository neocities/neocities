Sequel.migration do
  up {
    DB.create_table! :blocked_ips do
      String :ip, primary_key: true
      DateTime :created_at
    end
  }

  down {
    DB.drop_table :blocked_ips
  }
end