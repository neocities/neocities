Sequel.migration do
  up {
    DB.rename_column :events, :comment_id, :profile_comment_id

    DB.create_table! :profile_comments do
      primary_key :id
      Integer  :site_id
      Integer  :actioning_site_id
      Text     :message
      DateTime :created_at
      DateTime :updated_at
    end
  }

  down {
    DB.rename_column :events, :profile_comment_id, :comment_id
    DB.drop_table :profile_comments
  }
end