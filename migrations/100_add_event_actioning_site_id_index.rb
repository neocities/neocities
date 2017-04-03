Sequel.migration do
  up {
    DB.add_index :events, :actioning_site_id
  }

  down {
    DB.drop_index :events, :actioning_site_id
  }
end
