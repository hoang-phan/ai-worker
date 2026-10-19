# Keys for `encrypts` (Project#uat_password). Set the three ACTIVE_RECORD_ENCRYPTION_* env vars
# (`bin/rails db:encryption:init` prints values) to pin them; otherwise they are derived from
# secret_key_base, so rotating that secret makes existing encrypted values unreadable.
Rails.application.config.active_record.encryption.tap do |encryption|
  generator = -> { Rails.application.key_generator }
  encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || generator.call.generate_key("active_record_encryption.primary_key", 32).unpack1("H*")
  encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || generator.call.generate_key("active_record_encryption.deterministic_key", 32).unpack1("H*")
  encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || generator.call.generate_key("active_record_encryption.salt", 32).unpack1("H*")
end
