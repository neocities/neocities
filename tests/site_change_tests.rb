# frozen_string_literal: true
require_relative './environment'

describe SiteChange do
  it 'returns up to ten changed filenames by default' do
    site = Fabricate :site
    site_change = SiteChange.create site: site
    base_time = Time.now

    11.times do |i|
      site_change.add_site_change_file site_id: site.id, filename: "page#{i}.html", created_at: base_time + i
    end

    filenames = site_change.site_change_filenames

    _(filenames.length).must_equal 10
    _(filenames).must_include 'page10.html'
    _(filenames).wont_include 'page0.html'
  end
end
