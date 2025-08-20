class Report < Sequel::Model
	many_to_one :site
	many_to_one :reporting_site, class: :Site

	def site_file
		return nil unless site_file_path && site
		site.site_files_dataset.where(path: site_file_path).first
	end
end