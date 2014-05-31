Sequel.migration do
  up {
    DB.drop_column :events, :created_at
    DB.add_column :events, :created_at, :timestamp, index: true
  }

  down {
    DB.drop_column :events, :created_at
    DB.add_column :events, :created_at, :integer, index: true
  }
end
