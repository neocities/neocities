Sequel.migration do
  up {
    DB['alter table follows add constraint one_follow_per_site unique (site_id, actioning_site_id)'].first
  }

  down {
    DB['alter table follows drop constraint one_follow_per_site'].first
  }
end
