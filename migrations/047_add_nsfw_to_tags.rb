Sequel.migration do
  up {
    DB.add_column :tags, :is_nsfw, :boolean, default: false, index: true
  }

  down {
    DB.drop_column :tags, :is_nsfw
  }
end