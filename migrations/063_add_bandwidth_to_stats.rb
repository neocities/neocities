Sequel.migration do
  up {
    add_column :stats, :bandwidth, :bigint, default: 0
  }

  down {
    drop_column :stats, :bandwidth
  }
end
