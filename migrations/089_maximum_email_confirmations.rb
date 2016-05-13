Sequel.migration do
  up {
    DB.add_column :sites, :email_confirmation_count, :integer, default: 0

  }

  down {
    DB.drop_column :sites, :email_confirmation_count
  }
end
