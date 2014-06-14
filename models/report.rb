class Report < Sequel::Model
	many_to_one :site
	many_to_one :reporting_site, class: :Site
end