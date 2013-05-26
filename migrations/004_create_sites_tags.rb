Sequel.migration do
  up {
    DB.create_table! :sites_tags do
      foreign_key :site_id, :sites
      foreign_key :tag_id, :tags
    end
  }

  down {
    DB.drop_table :sites_tags
  }
end