# Clears the test memory store so AgentSetting / Rotation state (and anything
# else written to Rails.cache) cannot leak between examples.
RSpec.configure do |config|
  config.before { Rails.cache.clear }
end
