Sequel.migration do
  up {
    DB.create_table! :site_tags do
      Integer :site_id
      Integer :tag_id
    end
  }

  down {
    DB.drop_table :site_tags
  }
end