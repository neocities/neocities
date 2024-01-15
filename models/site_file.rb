# frozen_string_literal: true

require 'sanitize'

class SiteFile < Sequel::Model
  CLASSIFIER_LIMIT = 1_000_000
  CLASSIFIER_WORD_LIMIT = 25
  FILE_PATH_CHARACTER_LIMIT = 300
  FILE_NAME_CHARACTER_LIMIT = 100
  unrestrict_primary_key
  plugin :update_primary_key
  many_to_one :site

  def self.path_too_long?(filename)
    return true if filename.length > FILE_PATH_CHARACTER_LIMIT
    false
  end

  def self.name_too_long?(filename)
    return true if filename.length > FILE_NAME_CHARACTER_LIMIT
    false
  end

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

  def rename(new_path)
    current_path = self.path
    new_path = site.scrubbed_path new_path

    if new_path == ''
      return false, 'cannot rename to empty path'
    end

    if current_path == 'index.html'
      return false, 'cannot rename or move root index.html'
    end

    if site.site_files.select {|sf| sf.path == new_path}.length > 0
      return false, "#{is_directory ? 'directory' : 'file'} already exists"
    end

    unless is_directory
      mime_type = Magic.guess_file_mime_type site.files_path(self.path)
      extname = File.extname new_path

      unless site.supporter? || site.class.valid_file_mime_type_and_ext?(mime_type, extname)
        return false, 'unsupported file type'
      end
    end

    begin
      FileUtils.mv site.files_path(path), site.files_path(new_path)
      site.delete_thumbnail_or_screenshot current_path
      site.generate_thumbnail_or_screenshot new_path
    rescue Errno::ENOENT => e
      return false, 'destination directory does not exist' if e.message =~ /No such file or directory/i
      raise e
    rescue ArgumentError => e
      raise e unless e.message =~ /same file/
    end

    DB.transaction do
      self.path = new_path
      self.save_changes
      site.purge_cache current_path
      site.purge_cache new_path

      if is_directory
        site_files_in_dir = site.site_files.select {|sf| sf.path =~ /^#{current_path}\//}
        site_files_in_dir.each do |site_file|
          original_site_file_path = site_file.path
          site_file.path = site_file.path.gsub(/^#{current_path}\//, "#{new_path}\/")
          site_file.save_changes
          site.delete_thumbnail_or_screenshot original_site_file_path
          site.generate_thumbnail_or_screenshot site_file.path
          site.purge_cache site_file.path
          site.purge_cache original_site_file_path
        end
      end
    end

    return true, nil
  end

  def after_destroy
    super
    unless is_directory
      DB['update sites set space_used=space_used-? where id=?', size, site_id].first
    end

    site.purge_cache site.files_path(path)
    SiteChangeFile.filter(site_id: site_id, filename: path).delete
  end
end
