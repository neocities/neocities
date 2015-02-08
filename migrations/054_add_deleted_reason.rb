Sequel.migration do
  up {
    DB.add_column :sites, :deleted_reason, :text
  }

  down {
    DB.drop_column :sites, :deleted_reason
  }
end