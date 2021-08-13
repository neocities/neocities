require_relative '../environment.rb'

describe ArchiveWorker do
  it 'stores an IPFS archive' do
    return if ENV['CI']
    site = Fabricate :site
    ipfs_hash = site.add_to_ipfs
    ArchiveWorker.new.perform site.id
    site.archives.length.must_equal 1
    archive_one = site.archives.first
    archive_one.ipfs_hash.must_equal ipfs_hash
    archive_one.updated_at.wont_be_nil

    new_updated_at = Time.now - 500
    archive_one.update updated_at: new_updated_at

    ArchiveWorker.new.perform site.id
    archive_one.reload.updated_at.wont_equal new_updated_at

    site.store_files [{filename: 'test.jpg', tempfile: Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')}]
    ArchiveWorker.new.perform site.id

    site.reload
    site.archives.length.must_equal 2
    archive_two = site.archives_dataset.exclude(ipfs_hash: archive_one.ipfs_hash).first
    archive_two.ipfs_hash.wont_be_nil
  end
end
