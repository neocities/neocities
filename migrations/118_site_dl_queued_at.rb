Sequel.migration do
  up {
    DB.add_column :sites, :dl_queued_at, Time
  }

  down {
    DB.drop_column :sites, :dl_queued_at
  }
end
