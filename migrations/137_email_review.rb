# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :sites, :email_reviewed_at, DateTime
  end

  down do
    drop_column :sites, :email_reviewed_at
  end
end
