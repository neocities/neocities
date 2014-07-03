Sequel.migration do
  change do
  	alter_table(:events) { add_index :created_at }
    alter_table(:sites) { add_index :updated_at }
  	alter_table(:comment_likes) { add_index :comment_id }
  	alter_table(:comment_likes) { add_index :actioning_site_id }
  	alter_table(:sites_tags) { add_index :tag_id }
  	alter_table(:tags) { add_index :name }
  end
end