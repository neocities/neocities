class Archive < Sequel::Model
  many_to_one :site
  set_primary_key [:site_id, :ipfs_hash]
  unrestrict_primary_key

  def url
    "https://#{ipfs_hash}.ipfs.neocities.org"
  end
end
