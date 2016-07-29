Sequel.migration do
  up {
    DB.add_column :sites, :dashboard_accessed, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :dashboard_accessed
  }
end
