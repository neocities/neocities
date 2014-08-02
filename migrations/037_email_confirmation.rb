Sequel.migration do
  up {
    DB.add_column :sites, :email_confirmation_token, :text
    DB.add_column :sites, :email_confirmed, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :email_confirmation_token
    DB.drop_column :sites, :email_confirmed
  }
end