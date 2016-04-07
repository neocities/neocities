Sequel.migration do
  up {
    DB.drop_column :sites, :gandi_handle
    DB.drop_column :sites, :gandi_password

    DB.create_table! :domains do
      primary_key :id
      Integer  :site_id, index: true
      String   :gandi_handle
      String   :gandi_password
      String   :gandi_domain_id
      String   :name
      DateTime :created_at
      DateTime :released_at
    end
  }

  down {
    DB.drop_table :domains
    DB.add_column :sites, :gandi_handle, :text, index: true
    DB.add_column :sites, :gandi_password, :text
  }
end
