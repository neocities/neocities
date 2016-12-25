Sequel.migration do
  up {
    DB.add_column :sites, :tipping_enabled, :boolean, default: false
    DB.add_column :sites, :tipping_paypal, String
    DB.add_column :sites, :tipping_bitcoin, String
  }

  down {
    DB.drop_column :sites, :tipping_enabled
    DB.drop_column :sites, :tipping_paypal
    DB.drop_column :sites, :tipping_bitcoin
  }
end
