require 'base32'

class Archive < Sequel::Model
  many_to_one :site
  set_primary_key [:site_id, :ipfs_hash]
  unrestrict_primary_key
  MAXIMUM_ARCHIVES_PER_SITE = 10
  ARCHIVE_WAIT_TIME = 1.minute

  def before_destroy
    unpin
    super
  end

  def unpin
    return nil
    # Not ideal. An SoA version is in progress.
    if ENV['RACK_ENV'] == 'production' && $config['ipfs_ssh_host'] && $config['ipfs_ssh_user']
      rbox = Rye::Box.new $config['ipfs_ssh_host'], :user => $config['ipfs_ssh_user']
      rbox.disable_safe_mode
      begin
        response = rbox.execute "ipfs pin rm #{ipfs_hash}"
        output_array = response
      rescue => e
        return true if e.message =~ /indirect pins cannot be removed directly/
      ensure
        rbox.disconnect
      end
    else
      line = Terrapin::CommandLine.new('ipfs', 'pin rm :ipfs_hash')
      response = line.run ipfs_hash: ipfs_hash
      output_array = response.to_s.split("\n")
    end
  end

  def url
    "https://#{ipfs_hash}.ipfs.neocitiesops.net"
  end
end
