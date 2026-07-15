# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :sites, :email_recovery_email, :text
    add_column :sites, :email_recovery_token_digest, :text
    add_column :sites, :email_recovery_expires_at, DateTime
    add_index :sites, :email_recovery_token_digest, unique: true
  end

  down do
    drop_index :sites, :email_recovery_token_digest
    drop_column :sites, :email_recovery_expires_at
    drop_column :sites, :email_recovery_token_digest
    drop_column :sites, :email_recovery_email
  end
end
