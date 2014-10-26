Sequel.migration do
  up {
    DB.add_column :sites, :stripe_subscription_id, :text
  }

  down {
    DB.drop_column :sites, :stripe_subscription_id
  }
end