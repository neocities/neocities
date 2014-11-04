class SiteFile < Sequel::Model

  unrestrict_primary_key
  plugin :update_primary_key
  many_to_one :site
end