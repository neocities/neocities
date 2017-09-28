Sequel.migration do
  up {
    DB.add_column :sites, :github_deploy_key, :text
    DB.drop_column :sites, :github_access_token
  }

  down {
    DB.drop_column :sites, :github_deploy_key
    DB.add_column :sites, :github_access_token, :text
  }
end
