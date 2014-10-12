Sequel.migration do
  up {
    DB.add_column :sites, :parent_site_id, :integer, index: true
  }

  down {
    DB.drop_column :sites, :parent_site_id
  }
end