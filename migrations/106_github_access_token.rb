Sequel.migration do
  up {
    DB.add_column :sites, :github_access_token, :text
    DB.add_column :sites, :github_repo_name,    :text
  }

  down {
    DB.drop_column :sites, :github_access_token
    DB.drop_column :sites, :github_repo_name
  }
end
