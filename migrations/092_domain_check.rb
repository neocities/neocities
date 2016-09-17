Sequel.migration do
  up {
    DB.add_column :sites, :domain_fail_count, :integer, default: 0
  }

  down {
    DB.drop_column :sites, :domain_fail_count
  }
end
