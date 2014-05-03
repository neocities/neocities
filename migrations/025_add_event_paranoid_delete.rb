Sequel.migration do
  up {
    DB.add_column :events, :is_deleted, :boolean, default: false
  }

  down {
    DB.drop_column :events, :is_deleted
  }
end