Sequel.migration do
  up {
    DB.add_column :comments, :is_deleted, :boolean, default: false
  }

  down {
    DB.drop_column :comments, :is_deleted
  }
end