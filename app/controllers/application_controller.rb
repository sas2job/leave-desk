class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_string_fields!(values, *fields)
    fields.each do |field|
      next unless values.key?(field)

      raise ActionController::BadRequest, "Expected a string for #{field}" unless values[field].is_a?(String)
    end
    values
  end

  def require_identifier_fields!(values, *fields)
    fields.each do |field|
      next unless values.key?(field)

      value = values[field]
      next if value.nil? || value == ""
      next if value.is_a?(Integer) && value.positive?
      next if value.is_a?(String) && /\A[1-9]\d*\z/.match?(value)

      raise ActionController::BadRequest, "Expected an identifier for #{field}"
    end
    values
  end
end
