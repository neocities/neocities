Sequel.migration do
  up {
    DB.create_table! :banned_referrers do
      primary_key :id
      String   :name
    end
  }

  down {
    DB.drop_table :banned_referrers
  }
end
