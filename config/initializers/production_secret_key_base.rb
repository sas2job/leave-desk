if Rails.env.production?
  secret_key_base = ENV["SECRET_KEY_BASE"]&.strip

  if secret_key_base.blank? || secret_key_base == "generate-with-bin-rails-secret"
    raise "Production SECRET_KEY_BASE must be a unique secret"
  end
end
