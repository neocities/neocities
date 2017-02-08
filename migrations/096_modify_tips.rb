Sequel.migration do
  up {
    DB.add_column :tips, :currency, :text
    DB.add_column :tips, :message, :text
    DB.add_column :tips, :paypal_payer_email, :text
    DB.add_column :tips, :paypal_receiver_email, :text
    DB.add_column :tips, :paypal_txn_id, :text
    DB.add_column :tips, :fee, :numeric
  }

  down {
    DB.drop_column :tips, :currency
    DB.drop_column :tips, :message
    DB.drop_column :tips, :paypal_payer_email
    DB.drop_column :tips, :paypal_receiver_email
    DB.drop_column :tips, :paypal_txn_id
    DB.drop_column :tips, :fee
  }
end
