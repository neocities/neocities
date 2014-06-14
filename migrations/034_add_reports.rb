Sequel.migration do
  up {
    DB.create_table! :reports do
      primary_key :id
      Integer  :site_id
      Integer  :reporting_site_id
      String   :type
      Text     :comments
      Text     :action_taken
      String   :ip
      DateTime :created_at
    end
  }

  down {
    DB.drop_table :reports
  }
end