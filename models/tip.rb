class Tip < Sequel::Model
  many_to_one :site
  many_to_one :actioning_site, class: :Site

  def amount_string
    Monetize.parse("#{currency} #{amount.to_f}").format
  end

  def fee_string
    Monetize.parse("#{currency} #{fee.to_f}").format
  end
end
