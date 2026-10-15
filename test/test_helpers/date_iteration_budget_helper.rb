module DateIterationBudgetHelper
  def count_date_successors
    count = 0
    trace = TracePoint.new(:c_call) do |event|
      count += 1 if event.defined_class == Date && event.method_id == :succ
    end
    trace.enable { yield }
    count
  end
end
