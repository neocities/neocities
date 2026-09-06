# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :sites, :session_version, Integer, default: 0, null: false
  end

  down do
    drop_column :sites, :session_version
  end
end
