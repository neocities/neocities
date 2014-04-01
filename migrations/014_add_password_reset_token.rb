Sequel.migration do
  up {
    DB.add_column :sites, :password_reset_token, :text
    DB.add_index  :sites, :password_reset_token
  }

  down {
    DB.drop_column :sites, :password_reset_token
  }
end