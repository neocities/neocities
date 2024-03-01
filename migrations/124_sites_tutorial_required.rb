Sequel.migration do
  up {
    DB.add_column :sites, :tutorial_required, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :tutorial_required
  }
end