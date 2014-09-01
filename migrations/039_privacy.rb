Sequel.migration do
  up {
    DB.add_column :sites, :profile_comments_enabled, :boolean, default: true
  }

  down {
    DB.drop_column :sites, :profile_comments_enabled
  }
end
