Sequel.migration do
  up {
    DB.add_column :sites, :paypal_active, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :paypal_active
  }
end
