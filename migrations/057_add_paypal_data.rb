Sequel.migration do
  up {
    DB.add_column :sites, :paypal_profile_id, String
    DB.add_column :sites, :paypal_token, String
  }

  down {
    DB.drop_column :sites, :paypal_profile_id
    DB.drop_column :sites, :paypal_token
  }
end
