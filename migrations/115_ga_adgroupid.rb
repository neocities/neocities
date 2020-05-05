Sequel.migration do
  up {
    DB.add_column :sites, :ga_adgroupid, :text
  }

  down {
    DB.drop_column :sites, :ga_adgroupid
  }
end
