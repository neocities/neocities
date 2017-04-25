Sequel.migration do
  up {
    DB.add_index :sites, :parent_site_id
  }

  down {
    DB.drop_index :sites, :parent_site_id
  }
end
