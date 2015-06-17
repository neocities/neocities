Sequel.migration do
  up {
    %i{stat_referrers stat_locations stat_paths} do |t|
      DB.add_index t, :created_at
    end
  }

  down {
    %i{stat_referrers stat_locations stat_paths} do |t|
      DB.drop_index t, :created_at
    end
  }
end
