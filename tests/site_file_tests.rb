# frozen_string_literal: true
require_relative './environment.rb'
require 'rack/test'

describe 'site_files' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def upload(hash)
    post '/api/upload', hash.merge(csrf_token: 'abcd'), {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
  end

  def delete_file(hash)
    post '/site_files/delete', hash.merge(csrf_token: 'abcd'), {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
  end

  before do
    @site = Fabricate :site
    ThumbnailWorker.jobs.clear
    PurgeCacheWorker.jobs.clear
    PurgeCacheWorker.jobs.clear
    ScreenshotWorker.jobs.clear
  end

  describe 'rename' do
    before do
      PurgeCacheWorker.jobs.clear
    end

    it 'works with html file' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/notindex.html', 'text/html')
      upload 'notindex.html' => uploaded_file
      PurgeCacheWorker.jobs.clear
      testfile = @site.site_files_dataset.where(path: 'notindex.html').first
      testfile.rename 'notindex2.html'
      _(PurgeCacheWorker.jobs.length).must_equal 2
      _(PurgeCacheWorker.jobs.collect {|p| p['args'].last}.sort).must_equal ["/notindex", "/notindex2"]
    end

    it 'renames in same path' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => uploaded_file

      testfile = @site.site_files_dataset.where(path: 'test.jpg').first
      _(testfile).wont_equal nil
      testfile.rename 'derp.jpg'
      _(@site.site_files_dataset.where(path: 'derp.jpg').first).wont_equal nil
      _(PurgeCacheWorker.jobs.first['args'].last).must_equal '/test.jpg'
      _(File.exist?(@site.files_path('derp.jpg'))).must_equal true
    end

    it 'fails when file does not exist' do
      post '/site_files/rename', {path: 'derp.jpg', new_path: 'derp2.jpg', csrf_token: 'abcd'}, {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
      _(last_response.headers['Location']).must_match /dashboard/
      get '/dashboard', {}, {'rack.session' => { 'id' => @site.id, '_csrf_token' => 'abcd' }}
      _(last_response.body).must_match /file derp.jpg does not exist/i
    end

    it 'fails for bad extension change' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => uploaded_file

      testfile = @site.site_files_dataset.where(path: 'test.jpg').first
      res = testfile.rename('dasharezone.exe')
      _(res).must_equal [false, 'unsupported file type']
      _(@site.site_files_dataset.where(path: 'test.jpg').first).wont_equal nil
    end

    it 'renames nonstandard file type for supporters' do
      no_file_restriction_plans = Site::PLAN_FEATURES.select {|p,v| v[:no_file_restrictions] == true}
      no_file_restriction_plans.each do |plan_type,hash|
        @site = Fabricate :site, plan_type: plan_type.to_s
        upload 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
        testfile = @site.site_files_dataset.where(path: 'flowercrime.wav').first
        res = testfile.rename('flowercrime.exe')
        _(res.first).must_equal true
        _(File.exists?(@site.files_path('flowercrime.exe'))).must_equal true
        _(@site.site_files_dataset.where(path: 'flowercrime.exe').first).wont_equal nil
      end
    end

    it 'works for directory' do
      @site.create_directory 'dirone'
      _(@site.site_files.select {|sf| sf.path == 'dirone'}.length).must_equal 1

      dirone = @site.site_files_dataset.where(path: 'dirone').first
      _(dirone).wont_equal nil
      _(dirone.is_directory).must_equal true
      res = dirone.rename('dasharezone')
      _(res).must_equal [true, nil]
      dasharezone = @site.site_files_dataset.where(path: 'dasharezone').first
      _(dasharezone).wont_equal nil
      _(dasharezone.is_directory).must_equal true

      # No purge cache is executed because the directory is empty
    end

    it 'fails for directory name ending in .htm or .html' do
      @site.create_directory 'dirone'
      dirone = @site.site_files_dataset.where(path: 'dirone').first
      res = dirone.rename('dasharezone.html')
      _(res).must_equal [false, 'directory name cannot end with .htm or .html']
      res = dirone.rename('dasharezone.htm')
      _(res).must_equal [false, 'directory name cannot end with .htm or .html']
    end

    it 'fails when trying to move directory into itself' do
      @site.create_directory 'dir'
      dir = @site.site_files_dataset.where(path: 'dir').first
      res = dir.rename('dir/newdir')
      _(res).must_equal [false, 'cannot move directory into itself']
      _(@site.site_files_dataset.where(path: 'dir').first).wont_equal nil
      _(@site.site_files_dataset.where(path: 'dir/newdir').first).must_equal nil

      res = dir.rename('dir/sub/dir')
      _(res).must_equal [false, 'cannot move directory into itself']
      _(@site.site_files_dataset.where(path: 'dir').first).wont_equal nil
      _(@site.site_files_dataset.where(path: 'dir/sub/dir').first).must_equal nil
    end

    it 'wont set an empty directory' do
      @site.create_directory 'dirone'
      _(@site.site_files.select {|sf| sf.path == 'dirone'}.length).must_equal 1

      dirone = @site.site_files_dataset.where(path: 'dirone').first
      res = dirone.rename('')
      _(@site.site_files_dataset.where(path: '').count).must_equal 0
      _(res).must_equal [false, 'cannot rename to empty path']
      _(@site.site_files_dataset.where(path: '').count).wont_equal 1
    end

    it 'changes path of files and dirs within directory when changed' do
      upload 'test/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test/index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'image/jpeg')

      PurgeCacheWorker.jobs.clear

      @site.site_files.select {|s| s.path == 'test'}.first.rename('test2')

      _(@site.site_files.select {|sf| sf.path =~ /test2\/index.html/}.length).must_equal 1
      _(@site.site_files.select {|sf| sf.path =~ /test2\/test.jpg/}.length).must_equal 1
      _(@site.site_files.select {|sf| sf.path =~ /test\/test.jpg/}.length).must_equal 0

      _(PurgeCacheWorker.jobs.collect {|p| p['args'].last}.sort).must_equal ["/test/", "/test/test.jpg", "/test2/", "/test2/test.jpg",].sort
    end

    it 'doesnt wipe out existing file' do
      upload 'test/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test/index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'image/jpeg')

      res = @site.site_files_dataset.where(path: 'test/index.html').first.rename('test/test.jpg')
      _(res).must_equal [false, 'file already exists']
    end

    it 'doesnt wipe out existing dir' do
      @site.create_directory 'dirone'
      @site.create_directory 'dirtwo'
      res = @site.site_files.select{|sf| sf.path == 'dirtwo'}.first.rename 'dirone'
      _(res).must_equal [false, 'directory already exists']
    end

    it 'refuses to move index.html' do
      res = @site.site_files.select {|sf| sf.path == 'index.html'}.first.rename('notindex.html')
      _(res).must_equal [false, 'cannot rename or move root index.html']
    end

    it 'works with unicode characters' do
      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      @site.site_files_dataset.where(path: 'test.jpg').first.rename("HELL💩؋.jpg")
      _(@site.site_files_dataset.where(path: "HELL💩؋.jpg").first).wont_equal nil
    end

    it 'scrubs weird carriage return shit characters' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(proc {
        @site.site_files_dataset.where(path: 'test.jpg').first.rename("\r\n\t.jpg")
      }).must_raise ArgumentError
      _(_(@site.site_files_dataset.where(path: 'test.jpg').first)).wont_equal nil
    end
  end

  describe 'delete' do
    before do
      PurgeCacheWorker.jobs.clear
    end

    it 'works' do
      initial_space_used = @site.space_used
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => uploaded_file

      PurgeCacheWorker.jobs.clear

      _(@site.reload.space_used).must_equal initial_space_used + uploaded_file.size
      _(@site.actual_space_used).must_equal @site.space_used
      file_path = @site.files_path 'test.jpg'
      _(File.exists?(file_path)).must_equal true
      delete_file filename: 'test.jpg'

      _(File.exists?(file_path)).must_equal false
      _(SiteFile[site_id: @site.id, path: 'test.jpg']).must_be_nil
      _(@site.reload.space_used).must_equal initial_space_used
      _(@site.actual_space_used).must_equal @site.space_used

      args = PurgeCacheWorker.jobs.first['args']
      _(args[0]).must_equal @site.username
      _(args[1]).must_equal '/test.jpg'
    end

    it 'property deletes directories with regexp special chars in them' do
      upload '8)/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      delete_file filename: '8)'
      _(@site.reload.site_files.select {|f| f.path =~ /#{Regexp.quote '8)'}/}.length).must_equal 0
    end

    it 'deletes with escaped apostrophe' do
      upload "test'ing/test.jpg" => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(@site.reload.site_files.select {|s| s.path == "test'ing"}.length).must_equal 1
      delete_file filename: "test'ing"
      _(@site.reload.site_files.select {|s| s.path == "test'ing"}.length).must_equal 0
    end

    it 'deletes a directory and all files in it' do
      upload 'test/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')

      space_used = @site.reload.space_used
      delete_file filename: 'test'

      _(@site.reload.space_used).must_equal(space_used - File.size('./tests/files/test.jpg'))

      _(@site.site_files.select {|f| f.path == 'test'}.length).must_equal 0
      _(@site.site_files.select {|f| f.path =~ /^test\//}.length).must_equal 0
      _(@site.site_files.select {|f| f.path =~ /^test.jpg/}.length).must_equal 1
    end

    it 'deletes records for nested directories' do
      upload 'derp/ing/tons/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')

      expected_site_file_paths = ['derp', 'derp/ing', 'derp/ing/tons', 'derp/ing/tons/test.jpg']

      expected_site_file_paths.each do |path|
        _(@site.site_files.select {|f| f.path == path}.length).must_equal 1
      end

      delete_file filename: 'derp'

      @site.reload

      expected_site_file_paths.each do |path|
        _(@site.site_files.select {|f| f.path == path}.length).must_equal 0
      end
    end

    it 'goes back to deleting directory' do
      upload 'test/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      delete_file filename: 'test/test.jpg'
      _(last_response.headers['Location']).must_equal "http://example.org/dashboard?dir=test"

      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      delete_file filename: 'test.jpg'
      _(last_response.headers['Location']).must_equal "http://example.org/dashboard"
    end

    it 'deletes complex nested directory structure correctly' do
      upload 'complex/level1/level2/file1.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      upload 'complex/level1/level2/file2.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      upload 'complex/level1/file3.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      upload 'complex/level1/alt/file4.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      upload 'complex/file5.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')

      @site.reload
      complex_files = @site.site_files.select { |f| f.path.start_with?('complex') }
      _(complex_files.length).must_equal 9

      complex_dir = @site.site_files_dataset.where(path: 'complex').first
      complex_dir.destroy

      @site.reload
      remaining_files = @site.site_files.select { |f| f.path.start_with?('complex') }
      _(remaining_files.length).must_equal 0
    end

    it 'handles multiple destroy calls on same directory gracefully' do
      upload 'multitest/sub1/file1.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')
      upload 'multitest/sub2/file2.txt' => Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain')

      @site.reload
      test_dir = @site.site_files_dataset.where(path: 'multitest').first
      _(test_dir).wont_be_nil

      initial_files = @site.site_files.select { |f| f.path.start_with?('multitest') }
      _(initial_files.length).must_equal 5

      test_dir.destroy

      @site.reload
      remaining_files = @site.site_files.select { |f| f.path.start_with?('multitest') }
      _(remaining_files.length).must_equal 0

      _(proc { test_dir.destroy }).must_raise Sequel::NoExistingObject
    end
  end

  describe 'upload' do
    it 'works with empty files' do
      upload 'empty.js' => Rack::Test::UploadedFile.new('./tests/files/empty.js', 'text/javascript')
      _(File.exists?(@site.files_path('empty.js'))).must_equal true
    end

    it 'manages files with invalid UTF8' do
      upload 'invalidutf8.html' => Rack::Test::UploadedFile.new('./tests/files/invalidutf8.html', 'text/html')
      _(File.exists?(@site.files_path('invalidutf8.html'))).must_equal true
    end

    it 'works with manifest files' do
      upload 'cache.manifest' => Rack::Test::UploadedFile.new('./tests/files/cache.manifest', 'text/cache-manifest')
      _(File.exists?(@site.files_path('cache.manifest'))).must_equal true
    end

    it 'fails with filename greater than limit' do
      file_path = './tests/files' + (0...SiteFile::FILE_NAME_CHARACTER_LIMIT+1).map { ('a'..'z').to_a[rand(26)] }.join + '.html'
      begin
        File.open(file_path, "w") do |file|
          file.write("derp")
        end

        upload file_path => Rack::Test::UploadedFile.new(file_path, 'text/html')
        _(last_response.body).must_match /name is too long/i
      ensure
        FileUtils.rm file_path
      end
    end

    it 'fails with path greater than limit' do
      upload "#{(("a" * 50 + "/") * (SiteFile::FILE_PATH_CHARACTER_LIMIT / 50 - 1) + "a" * 50)}/test.jpg" => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(last_response.body).must_match /path is too long/i
    end

    it 'works with otf fonts' do
      upload 'chunkfive.otf' => Rack::Test::UploadedFile.new('./tests/files/chunkfive.otf', 'application/vnd.ms-opentype')
      _(File.exists?(@site.files_path('chunkfive.otf'))).must_equal true
    end

    it 'purges cache for html file with extension removed' do
      upload 'notindex.html' => Rack::Test::UploadedFile.new('./tests/files/notindex.html', 'text/html')
      _(PurgeCacheWorker.jobs.length).must_equal 1
      PurgeCacheWorker.new.perform @site.username, '/notindex.html'
      _(PurgeCacheWorker.jobs.first['args'].last).must_equal '/notindex'
    end

    it 'succeeds with index.html file' do
      _(@site.site_changed).must_equal false
      upload 'index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      _(last_response.body).must_match /successfully uploaded/i
      _(File.exists?(@site.files_path('index.html'))).must_equal true

      args = ScreenshotWorker.jobs.first['args']
      _(args.first).must_equal @site.username
      _(args.last).must_equal 'index.html'
      _(@site.title).must_equal "The web site of #{@site.username}"
      @site.reload
      _(@site.site_changed).must_equal true
      _(@site.title).must_equal 'Hello?'

      _(PurgeCacheWorker.jobs.length).must_equal 1
      first_purge = PurgeCacheWorker.jobs.first

      username, pathname = first_purge['args']
      _(username).must_equal @site.username
      _(pathname).must_equal '/'

      _(@site.space_used).must_equal @site.actual_space_used
      _((@site.space_used > 0)).must_equal true
    end

    it 'provides the correct space used after overwriting an existing file' do
      initial_space_used = @site.space_used
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => uploaded_file
      second_uploaded_file = Rack::Test::UploadedFile.new('./tests/files/img/test.jpg', 'image/jpeg')
      upload 'test.jpg' => second_uploaded_file
      _(@site.reload.space_used).must_equal initial_space_used + second_uploaded_file.size
      _(@site.space_used).must_equal @site.actual_space_used
    end

    it 'does not change title for subdir index.html' do
      title = @site.title
      upload(
        'derpie/index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      )
      _(@site.reload.title).must_equal title
    end

    it 'purges cache for /subdir/' do # (not /subdir which is just a redirect to /subdir/)
      upload(
        'subdir/index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      )
      _(PurgeCacheWorker.jobs.select {|j| j['args'].last == '/subdir/'}.length).must_equal 1
    end

    it 'succeeds with multiple files' do
      upload(
        'one/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg'),
        'two/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      )

      _(@site.site_files.select {|s| s.path == 'one'}.length).must_equal 1
      _(@site.site_files.select {|s| s.path == 'one/test.jpg'}.length).must_equal 1
      _(@site.site_files.select {|s| s.path == 'two'}.length).must_equal 1
      _(@site.site_files.select {|s| s.path == 'two/test.jpg'}.length).must_equal 1
    end

    it 'succeeds with valid file' do
      initial_space_used = @site.space_used
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      upload 'test.jpg' => uploaded_file
      _(last_response.body).must_match /successfully uploaded/i
      _(File.exists?(@site.files_path('test.jpg'))).must_equal true

      username, path = PurgeCacheWorker.jobs.first['args']
      _(username).must_equal @site.username
      _(path).must_equal '/test.jpg'

      @site.reload
      _(@site.space_used).wont_equal 0
      _(@site.space_used).must_equal initial_space_used + uploaded_file.size
      _(@site.space_used).must_equal @site.actual_space_used

      _(ThumbnailWorker.jobs.length).must_equal 1
      ThumbnailWorker.drain

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        _(File.exists?(@site.thumbnail_path('test.jpg', resolution))).must_equal true
      end

      _(@site.site_changed).must_equal false
    end

    it 'allows non-extension filename upload if it is a text or JSON file' do
      uploaded_files = [Rack::Test::UploadedFile.new('./tests/files/text-file', 'text/plain'), Rack::Test::UploadedFile.new('./tests/files/json-file', 'application/json')]

      uploaded_files.each do |file|
        upload file.original_filename => file
        _(last_response.body).must_match /successfully uploaded/i
        _(File.exists?(@site.files_path(file.original_filename))).must_equal true
        username, path = PurgeCacheWorker.jobs.last['args']
        _(username).must_equal @site.username
        _(path).must_equal '/'+file.original_filename
      end

      upload 'testjpeg' => Rack::Test::UploadedFile.new('./tests/files/testjpeg', 'image/jpeg')
      _(last_response.body).must_match /invalid_file_type/i
    end

    it 'works with square bracket filename' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/te[s]t.jpg', 'image/jpeg')
      upload 'te[s]t.jpg' => uploaded_file
      _(last_response.body).must_match /successfully uploaded/i
      _(File.exists?(@site.files_path('te[s]t.jpg'))).must_equal true
    end

    it 'works with question marks' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/te[s]t.jpg', 'image/jpeg')
      upload 'te?st.jpg' => uploaded_file
      _(last_response.body).must_match /successfully uploaded/i
      _(File.exists?(@site.files_path('te?st.jpg'))).must_equal true
    end

    it 'sets site changed to false if index is empty' do
      uploaded_file = Rack::Test::UploadedFile.new('./tests/files/blankindex/index.html', 'text/html')
      upload 'index.html' => uploaded_file
      _(last_response.body).must_match /successfully uploaded/i
      _(@site.empty_index?).must_equal true
      _(@site.site_changed).must_equal false
    end

    it 'fails with unsupported file' do
      upload 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')

      _(JSON.parse(last_response.body)['error_type']).must_equal 'invalid_file_type'
      _(File.exists?(@site.files_path('flowercrime.wav'))).must_equal false
      _(@site.site_changed).must_equal false
    end

    it 'succeeds for unwhitelisted file on supporter plans' do
      no_file_restriction_plans = Site::PLAN_FEATURES.select {|p,v| v[:no_file_restrictions] == true}
      no_file_restriction_plans.each do |plan_type,hash|
        @site = Fabricate :site, plan_type: plan_type.to_s
        upload 'flowercrime.wav' => Rack::Test::UploadedFile.new('./tests/files/flowercrime.wav', 'audio/x-wav')
        _(last_response.body).must_match /successfully uploaded/i
        _(File.exists?(@site.files_path('flowercrime.wav'))).must_equal true
      end
    end

    it 'overwrites existing file with new file' do
      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(last_response.body).must_match /successfully uploaded/i
      digest = @site.reload.site_files.first.sha1_hash
      upload 'test.jpg' => Rack::Test::UploadedFile.new('./tests/files/img/test.jpg', 'image/jpeg')
      _(last_response.body).must_match /successfully uploaded/i
      _(@site.reload.changed_count).must_equal 2
      _(@site.site_files.select {|f| f.path == 'test.jpg'}.length).must_equal 1
      _(digest).wont_equal @site.site_files_dataset.where(path: 'test.jpg').first.sha1_hash
    end

    it 'works with directory path' do
      upload 'derpie/derptest/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(last_response.body).must_match /successfully uploaded/i
      _(File.exists?(@site.files_path('derpie/derptest/test.jpg'))).must_equal true

      _(PurgeCacheWorker.jobs.length).must_equal 1
      username, path = PurgeCacheWorker.jobs.first['args']
      _(username).must_equal @site.username
      _(path).must_equal '/derpie/derptest/test.jpg'

      _(ThumbnailWorker.jobs.length).must_equal 1
      ThumbnailWorker.drain

      _(@site.site_files_dataset.where(path: 'derpie').count).must_equal 1
      _(@site.site_files_dataset.where(path: 'derpie/derptest').count).must_equal 1
      _(@site.site_files_dataset.where(path: 'derpie/derptest/test.jpg').count).must_equal 1

      Site::THUMBNAIL_RESOLUTIONS.each do |resolution|
        _(File.exists?(@site.thumbnail_path('derpie/derptest/test.jpg', resolution))).must_equal true
        _(@site.thumbnail_url('derpie/derptest/test.jpg', resolution)).must_equal(
          File.join "#{Site::THUMBNAILS_URL_ROOT}", Site.sharding_dir(@site.username), @site.username, "/derpie/derptest/test.jpg.#{resolution}.webp"
        )
      end
    end

    it 'works with unicode chars on filename and dir' do
      upload '詩經/詩經.jpg' => Rack::Test::UploadedFile.new('./tests/files/詩經.jpg', 'image/jpeg')
      _(@site.site_files_dataset.where(path: '詩經/詩經.jpg').count).must_equal 1
    end

    it 'does not register site changing until root index.html is changed' do
      upload 'derpie/derptest/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(@site.reload.site_changed).must_equal false

      upload 'index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      _(@site.reload.site_changed).must_equal true

      upload 'chunkfive.otf' => Rack::Test::UploadedFile.new('./tests/files/chunkfive.otf', 'application/vnd.ms-opentype')
      _(@site.reload.site_changed).must_equal true
    end

    it 'does not store new file if hash matches' do
      upload 'derpie/derptest/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(@site.reload.changed_count).must_equal 1

      upload 'derpie/derptest/test.jpg' => Rack::Test::UploadedFile.new('./tests/files/test.jpg', 'image/jpeg')
      _(@site.reload.changed_count).must_equal 1

      upload 'index.html' => Rack::Test::UploadedFile.new('./tests/files/index.html', 'text/html')
      _(@site.reload.changed_count).must_equal 2
    end

    describe 'classification' do
      before do
        puts "TODO FINISH CLASSIFIER"
        #$trainer.instance_variable_get('@db').redis.flushall
      end
    end
  end
end
