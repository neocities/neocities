Sequel.migration do
  up {
    DB.add_column :sites, :plan_type, :text
  }

  down {
    DB.drop_column :sites, :plan_type
  }
end