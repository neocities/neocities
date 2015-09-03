require 'base32'

class Archive < Sequel::Model
  many_to_one :site
  set_primary_key [:site_id, :ipfs_hash]
  unrestrict_primary_key

  def self.base58_to_hshca(base58)
    Base32.encode(Base58.base58_to_bytestring(base58)).gsub('=', '').downcase
  end

  def hshca_hash
    self.class.base58_to_hshca ipfs_hash
  end

  def url
    "http://#{hshca_hash}.ipfs.neocitiesops.net"
  end
end
