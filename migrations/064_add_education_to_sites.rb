Sequel.migration do
  up {
    add_column :sites, :is_education, :boolean, default: false
  }

  down {
    drop_column :sites, :is_education
  }
end
