Sequel.migration do
  up {
    DB.add_column :sites, :is_nsfw, :boolean, default: false
  }

  down {
    DB.add_column :sites, :is_nsfw
  }
end