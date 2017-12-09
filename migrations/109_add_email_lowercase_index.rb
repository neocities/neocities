Sequel.migration do
  up {
    DB['CREATE INDEX sites_email_lower_index ON sites (LOWER(email))'].first
  }

  down {
    DB['DROP INDEX sites_email_lower_index'].first
  }
end
