Sequel.migration do
  up {
    DB.add_column :sites, :phone_verification_attempts, :integer, default: 0
  }

  down {
    DB.drop_column :sites, :phone_verification_attempts
  }
end