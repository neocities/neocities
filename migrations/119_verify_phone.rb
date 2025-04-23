Sequel.migration do
  up {
    DB.add_column :sites, :phone_verification_required, :boolean, default: false
    DB.add_column :sites, :phone_verified, :boolean, default: false
    DB.add_column :sites, :phone_verification_sid, :text
    DB.add_column :sites, :phone_verification_sent_at, :time
  }

  down {
    DB.drop_column :sites, :phone_verification_required
    DB.drop_column :sites, :phone_verified
    DB.drop_column :sites, :phone_verification_sid
    DB.drop_column :sites, :phone_verification_sent_at
  }
end