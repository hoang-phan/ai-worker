module AiCli
  # Round robin of agent CLIs across workflows, so no single CLI's usage limits (claude and codex are capped per
  # 4-5 hours and per week) are exhausted by leaving the scheduler running. Weights say how many consecutive
  # workflows each provider gets per cycle, e.g. claude 5, codex 3, cursor 1: five on claude, three on codex, one
  # on cursor, then again. Stored in Rails.cache like AgentSetting; all-zero (the default) turns it off, and
  # workflows then use the app-wide agent. Non-workflow tasks (brainstorm, syncs) never rotate.
  module Rotation
    WEIGHTS_KEY = "ai_cli/rotation/weights".freeze
    COUNTER_KEY = "ai_cli/rotation/counter".freeze

    module_function

    # { "claude" => 5, "codex" => 3, "cursor" => 0 } for every known provider, in display order.
    def weights
      stored = Rails.cache.read(WEIGHTS_KEY) || {}
      Providers.names.index_with { |name| stored[name].to_i.clamp(0..) }
    end

    def weights=(hash)
      hash = hash.to_h.transform_keys(&:to_s)
      unknown = hash.keys - Providers.names
      raise ArgumentError, "unknown agent #{unknown.first.inspect} (expected one of #{Providers.names.join(", ")})" if unknown.any?

      parsed = hash.transform_values do |value|
        Integer(value.to_s.presence || 0, exception: false) || raise(ArgumentError, "weights must be whole numbers, got #{value.inspect}")
      end
      raise ArgumentError, "weights cannot be negative" if parsed.values.any?(&:negative?)

      Rails.cache.write(WEIGHTS_KEY, weights.merge(parsed))
      Rails.cache.write(COUNTER_KEY, 0)
    end

    def enabled?
      weights.values.sum.positive?
    end

    # The provider for the next workflow, advancing the cycle; nil when rotation is off.
    def next_provider
      current = weights
      total = current.values.sum
      return unless total.positive?

      counter = Rails.cache.read(COUNTER_KEY).to_i
      Rails.cache.write(COUNTER_KEY, (counter + 1) % total)
      slot = counter % total
      current.each do |name, weight|
        return name if slot < weight

        slot -= weight
      end
    end
  end
end
