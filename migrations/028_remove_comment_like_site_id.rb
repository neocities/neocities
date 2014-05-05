Sequel.migration do
  up {
    DB.drop_column :comment_likes, :site_id
  }

  down {
    DB.add_column :comment_likes, :site_id, :integer
  }
end
