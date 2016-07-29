Sequel.migration do
  up {
    DB.add_column :sites, :custom_max_space, :bigint, default: 0
  }

  down {
    DB.drop_column :sites, :custom_max_space
  }
end
