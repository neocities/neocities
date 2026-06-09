# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :sites, :nsfw_opt_in, :boolean, default: false
  end

  down do
    drop_column :sites, :nsfw_opt_in
  end
end
