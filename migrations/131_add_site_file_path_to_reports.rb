Sequel.migration do
  change do
    add_column :reports, :site_file_path, String
  end
end