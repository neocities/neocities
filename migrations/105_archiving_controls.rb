Sequel.migration do
  up {
    DB.add_column :sites, :archiving_disabled, :boolean, default: false
    DB.add_column :sites, :archiving_private,  :boolean, default: false
  }

  down {
    DB.drop_column :sites, :archiving_disabled
    DB.drop_column :sites, :archiving_private
  }
end
