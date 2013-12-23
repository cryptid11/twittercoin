module BitcoinAPI
  extend self
  extend Bitcoin::Builder

  def generate_address()
    private_key, public_key = Bitcoin::generate_key
    address = Bitcoin::pubkey_to_address(public_key)
    encrypted_private_key = AES.encrypt(private_key, DECRYPTION_KEY)
    {
      encrypted_private_key: encrypted_private_key,
      public_key: public_key,
      address: address
    }
  end

  # string address
  def get_info(address)
    BitcoinNodeAPI.get_addr(address)
  end

  # obj address, int amount
  # returns httparty response obj
  # exception is raised, ensure to rescue
  # BitcoinAPI.send_tx(from_address, "15TLNJ24UFixU1Vn7eogJYvgaH324SocK4", 0.001.to_satoshi, FEE)
  def send_tx(from_address, to_address, amount, fee = FEE)
    raise AmountShouldBeFixnum if amount.class != Fixnum
    hex, tx_hash = construct_tx(from_address, to_address, amount, fee)
    push_tx(hex, tx_hash)
    return tx_hash
  end

  def construct_tx(from_address, to_address, amount, fee)
    unspents = get_unspents(from_address.address, amount + fee)
    prikey = from_address.decrypt()
    key = Bitcoin::Key.new(prikey, nil, false)

    new_tx = build_tx do |t|
      unspents.each do |unspent|
        t.input do |i|
          i.prev_out(Bitcoin::P::Tx.new(BitcoinNodeAPI.get_tx(unspent["tx_hash"].reverse_hex)))
          i.prev_out_index(unspent["tx_output_n"])
          i.signature_key(key)
        end
      end

      t.output do |o|
        o.value(amount)
        o.script {|s| s.recipient(to_address) }
      end

      t.output do |o|
        o.value(unspents.unspent_value - (amount+fee))
        o.script {|s| s.recipient key.addr }
      end
    end

    return new_tx.payload.unpack("H*").first, new_tx.hash
  end

  def get_unspents(from_address, total_value)
    unspents = BitcoinNodeAPI.unspent([from_address])
    select_unspents(unspents, total_value)
  end

  def select_unspents(unspents, total_value)
    raise InsufficientAmount.new("Needed #{total_value}, but only had #{unspents.unspent_value}") if unspents.unspent_value < (total_value)
    selected_unspents = []
    unspents.each do |unspent|
      if unspent["value"] >= total_value
        return [unspent]
      else
        selected_unspents << unspent
        return selected_unspents if selected_unspents.unspent_value >= total_value
      end
    end
  end

  def push_tx(hex, tx_hash)
    BitcoinNodeAPI.push_tx(hex, tx_hash)
  end

  class TxError < StandardError; end
  class InsufficientAmount < TxError; end
  class AmountShouldBeInteger < TxError; end

  class ::Array
    def unspent_value
      self.sum { |unspent| unspent["value"] }
    end
  end

  class ::String
    def reverse_hex
      [self].pack('H*').reverse.unpack("H*").first
    end
  end
end
