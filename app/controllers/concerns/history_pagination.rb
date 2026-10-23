module HistoryPagination
  PAGE_SIZE = 25
  MAX_CURSOR_ID = 9_223_372_036_854_775_807

  private

  def paginate_history(scope)
    @history_cursor = history_cursor
    scope = scope.where(scope.klass.arel_table[:id].lt(@history_cursor)) if @history_cursor
    records = scope.reorder(scope.klass.arel_table[:id].desc).limit(PAGE_SIZE + 1).to_a
    @history_next_cursor = records[PAGE_SIZE - 1].id if records.size > PAGE_SIZE
    records.first(PAGE_SIZE)
  end

  def history_cursor
    raw = params[:before]
    return if raw.nil?

    unless raw.is_a?(String) && raw.valid_encoding? && raw.match?(/\A[1-9]\d{0,18}\z/) &&
        raw.to_i <= MAX_CURSOR_ID
      raise ActionController::BadRequest, "Некорректный курсор страницы"
    end

    raw.to_i
  end
end
