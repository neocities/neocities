class BitcoinValidator
  class << self
    def address_version
      "00"
    end

    def p2sh_version
      "05"
    end

    def valid_address?(address)
      hex = decode_base58(address) rescue nil
      return false unless hex && hex.bytesize == 50
      return false unless [address_version, p2sh_version].include?(hex[0...2])
      base58_checksum?(address)
    end

    def decode_base58(base58_val)
      s = base58_to_int(base58_val).to_s(16); s = (s.bytesize.odd? ? '0'+s : s)
      s = '' if s == '00'
      leading_zero_bytes = (base58_val.match(/^([1]+)/) ? $1 : '').size
      s = ("00"*leading_zero_bytes) + s  if leading_zero_bytes > 0
      s
    end

    def base58_checksum?(base58)
      hex = decode_base58(base58) rescue nil
      return false unless hex
      checksum( hex[0...42] ) == hex[-8..-1]
    end

    def checksum(hex)
      b = [hex].pack("H*") # unpack hex
      Digest::SHA256.hexdigest( Digest::SHA256.digest(b) )[0...8]
    end


    def base58_to_int(base58_val)
      alpha = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
      int_val, base = 0, alpha.size
      base58_val.reverse.each_char.with_index do |char,index|
        raise ArgumentError, 'Value not a valid Base58 String.' unless char_index = alpha.index(char)
        int_val += char_index*(base**index)
      end
      int_val
    end

  end
end
