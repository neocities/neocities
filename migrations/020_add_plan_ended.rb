Sequel.migration do
  up {
    DB.add_column  :sites, :plan_ended, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :plan_ended
  }
end