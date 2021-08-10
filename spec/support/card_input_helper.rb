module SolidusCardInputHelper
  def fill_in_expiration(field_name, month, year)
    "#{month}#{year.last(2)}".split("").each { |n| find_field(field_name).native.send_keys(n) }
  end

  def fill_in_number(field_name, number)
    number.to_s.split("").each { |n| find_field(field_name).native.send_keys(n) }
  end
end
