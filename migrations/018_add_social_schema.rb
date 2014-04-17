Sequel.migration do
  up {
    DB.add_column :sites, :title, :text, default: nil
    DB.add_column :sites, :twitter_handle, :text, default: nil
    DB.add_column :sites, :views, :integer, default: 0
    DB.add_column :sites, :stripe_token, :text, default: nil

    DB.create_table! :follows do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :actioning_site_id, index: true
      DateTime    :created_at, index: true
    end

    DB.create_table! :tips do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :actioning_site_id, index: true
      DateTime    :created_at, index: true
      BigDecimal  :amount
      Integer     :stripe_charge_id
    end

    DB.create_table! :changes do
      primary_key :id
      Integer     :site_id, index: true
      DateTime    :created_at, index: true
    end

    DB.create_table! :events do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :follow_id
      Integer     :tip_id
      Integer     :tag_id
      Integer     :site_update_id
      Integer     :comment_id
      Boolean     :notification_seen, default: false
      Integer     :created_at, index: true
    end
    
    DB.create_table! :comments do
      primary_key :id
      Integer     :event_id, index: true
      Integer     :actioning_site_id
      Integer     :parent_comment_id
      Text        :message
      DateTime    :created_at
      DateTime    :updated_at
    end
    
    DB.create_table! :likes do
      primary_key :id
      Integer     :event_id, index: true
      Integer     :actioning_site_id
      DateTime    :created_at
    end
    
    DB.create_table! :stats do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :hits, default: 0
      Integer     :views, default: 0
      DateTime    :created_at, index: true
    end
    
    DB.create_table! :blocks do
      primary_key :id
      Integer     :site_id, index: true
      Integer     :actioning_site_id, index: true
      DateTime    :created_at
    end
  }

  down {
    DB.drop_column :sites, :title
    DB.drop_column :sites, :twitter_handle
    DB.drop_column :sites, :views
    DB.drop_column :sites, :stripe_token

    DB.drop_table :follows
    DB.drop_table :tips
    DB.drop_table :changes
    DB.drop_table :events
    DB.drop_table :comments
    DB.drop_table :likes
    DB.drop_table :stats
    DB.drop_table :blocks
  }
end