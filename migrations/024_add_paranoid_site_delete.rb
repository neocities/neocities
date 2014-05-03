Sequel.migration do
  up {
    DB.add_column :sites, :is_deleted, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :is_deleted
  }
end