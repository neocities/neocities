Sequel.migration do
  up {
    DB.add_column :sites, :gandi_handle, :text, index: true

    # This is not as horrible as it looks.
    # It basically serves as a temp password when account is released from reseller account.
    DB.add_column :sites, :gandi_password, :text
  }

  down {
    DB.drop_column :sites, :gandi_handle
    DB.drop_column :sites, :gandi_password
  }
end
