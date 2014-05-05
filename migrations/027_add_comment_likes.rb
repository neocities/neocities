Sequel.migration do
  up {
    DB.create_table! :comment_likes do
      primary_key :id
      Integer  :comment_id
      Integer  :site_id
      Integer  :actioning_site_id
      DateTime :created_at
    end
  }

  down {
    DB.drop_table :comment_likes
  }
end
