Sequel.migration do
  up {
    DB.drop_column :sites, :phone_verification_sent_at
    DB.add_column :sites, :phone_verification_sent_at, Time
  }

  down {
    DB.drop_column :sites, :phone_verification_sent_at
    DB.add_column :sites, :phone_verification_sent_at, :time
  }
end