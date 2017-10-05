Sequel.migration do
  up {
    DB.add_column :sites, :email_invoice, :boolean, default: false
  }

  down {
    DB.drop_column :sites, :email_invoice
  }
end
