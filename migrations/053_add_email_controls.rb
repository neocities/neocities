Sequel.migration do
  up {
    DB.add_column :sites, :send_emails, :boolean, default: true
    DB.add_column :sites, :send_comment_emails, :boolean, default: true
    DB.add_column :sites, :send_follow_emails, :boolean, default: true
  }

  down {
    DB.drop_column :sites, :send_emails
    DB.drop_column :sites, :send_comment_emails
    DB.drop_column :sites, :send_follow_emails
  }
end