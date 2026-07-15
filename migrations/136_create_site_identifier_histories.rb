# frozen_string_literal: true

Sequel.migration do
  up do
    create_table :site_identifier_histories do
      primary_key :id
      foreign_key :site_id, :sites, null: false, on_delete: :cascade
      String :identifier_type, null: false, size: 16
      String :identifier, null: false, size: 254
      DateTime :changed_at, null: false

      index [:identifier_type, :identifier], name: :site_identifier_histories_lookup_idx
      index [:site_id, :identifier_type, :changed_at], name: :site_identifier_histories_site_type_changed_idx
    end
  end

  down do
    drop_table :site_identifier_histories
  end
end
