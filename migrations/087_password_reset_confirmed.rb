Sequel.migration do
  up {
    DB.add_column :sites, :password_reset_confirmed, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :password_reset_confirmed
  }
end
