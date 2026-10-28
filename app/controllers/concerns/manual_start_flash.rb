# Starts an AgentRuns::ManualStart from a CycleSource and maps its result to the
# redirect + flash the "run now" buttons show. Callers pass the source plus the
# label and the started / already-running texts.
module ManualStartFlash
  extend ActiveSupport::Concern

  private

  def start_source_manually(source, label:, started:, already_running:, to: @project)
    result = AgentRuns::ManualStart.for(source).call
    redirect_after_manual_start(result, to:, label:, started:, already_running:)
  end

  def redirect_after_manual_start(result, to:, label:, started:, already_running:)
    case result.status
    when :blocked
      redirect_to to, alert: "#{label} blocked: #{result.detail}"
    when :skipped
      redirect_to to, alert: "#{label} skipped: #{result.detail}"
    when :started
      redirect_to to, notice: started
    when :already_running
      redirect_to to, alert: already_running
    when :failed
      redirect_to to, alert: "#{label} failed: #{result.detail}"
    end
  end
end
