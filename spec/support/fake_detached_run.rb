# Stand-in for AiCli::DetachedRun in fetcher specs.
# Records the keyword args `start` receives and yields canned rows to `poll`.
class FakeDetachedRun
  attr_reader :started
  attr_accessor :last_started_at, :rows, :result_path

  def start(**kwargs)
    @started = kwargs
  end

  def running?
    false
  end

  def poll
    yield rows
  end
end
