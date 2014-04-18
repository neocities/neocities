Sequel.migration do
  up {
    DB.drop_column :sites, :stripe_token
    DB.add_column  :sites, :stripe_customer_id, :text, default: nil
  }

  down {
    DB.drop_column :sites, :stripe_customer_id
    DB.add_column  :sites, :stripe_token, :text, default: nil
  }
end