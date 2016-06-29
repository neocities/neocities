require 'sanitize'

class SiteFile < Sequel::Model
  CLASSIFIER_LIMIT = 1_000_000.freeze
  CLASSIFIER_WORD_LIMIT = 25.freeze
  unrestrict_primary_key
  plugin :update_primary_key
  many_to_one :site

  def before_destroy
    if is_directory
      site.site_files_dataset.where(path: /^#{Regexp.quote path}\//, is_directory: true).all.each do |site_file|
        begin
          site_file.destroy
        rescue Sequel::NoExistingObject
        end
      end

      site.site_files_dataset.where(path: /^#{Regexp.quote path}\//, is_directory: false).all.each do |site_file|
        site_file.destroy
      end

      begin
        FileUtils.remove_dir site.files_path(path)
      rescue Errno::ENOENT
      end

    else

      begin
        FileUtils.rm site.files_path(path)
      rescue Errno::ENOENT
      end

      ext = File.extname(path).gsub(/^./, '')
      site.screenshots_delete(path) if ext.match Site::HTML_REGEX
      site.thumbnails_delete(path) if ext.match Site::IMAGE_REGEX
    end

    super
  end

  def after_destroy
    super
    unless is_directory
      DB['update sites set space_used=space_used-? where id=?', size, site_id].first
    end

    site.delete_cache site.files_path(path)
    SiteChangeFile.filter(site_id: site_id, filename: path).delete
  end
end
