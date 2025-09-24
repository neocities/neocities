Sequel.migration do
  up {
    DB.add_column :sites, :needs_moderation, :boolean, default: true
  }

  down {
    DB.drop_column :sites, :needs_moderation
  }
end