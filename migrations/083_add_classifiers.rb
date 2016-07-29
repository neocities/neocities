Sequel.migration do
  up {
    DB.add_column :site_files, :classifier, :text, default: nil, index: true
  }

  down {
    DB.drop_column :site_files, :classifier
  }
end
