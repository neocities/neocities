Sequel.migration do
  up {
    DB.add_column :events, :actioning_site_id, :integer
  }

  down {
    DB.drop_column :events, :actioning_site_id
  }
end
