module LegalReviewParameters
  private

  def legal_review_params
    fields = %i[conditions_confirmed age_boundary_confirmed document_reference document_starts_on document_ends_on
      working_year_starts_on working_year_ends_on entitlement_days]
    raw = params[:legal_review]
    require_known_fields!(raw, *fields, container: "legal_review", example: '{"legal_review":{}}')
    if raw.is_a?(ActionController::Parameters)
      require_string_fields!(raw, :document_reference, :document_starts_on, :document_ends_on,
        :working_year_starts_on, :working_year_ends_on)
      require_identifier_fields!(raw, :entitlement_days)
    end
    attributes = params.expect(legal_review: fields).to_h.symbolize_keys
    confirmation = attributes[:conditions_confirmed]
    unless [ nil, "0", "1", "true", "false", true, false ].include?(confirmation)
      raise ActionController::BadRequest, "Invalid confirmation"
    end
    attributes[:conditions_confirmed] = [ "1", "true", true ].include?(confirmation)
    age_confirmation = attributes[:age_boundary_confirmed]
    unless [ nil, "0", "1", "true", "false", true, false ].include?(age_confirmation)
      raise ActionController::BadRequest, "Invalid age boundary confirmation"
    end
    attributes[:age_boundary_confirmed] = [ "1", "true", true ].include?(age_confirmation)
    %i[document_starts_on document_ends_on working_year_starts_on working_year_ends_on].each do |field|
      next unless attributes.key?(field)

      value = attributes[field]
      attributes[field] = Date.iso8601(value) if value&.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    rescue Date::Error
      attributes[field] = nil
    end
    attributes
  end
end
