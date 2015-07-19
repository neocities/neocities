Sequel.migration do
  up {
    DB.add_column :sites, :admin_nsfw, :boolean
  }

  down {
    DB.drop_column :sites, :admin_nsfw
  }
end
