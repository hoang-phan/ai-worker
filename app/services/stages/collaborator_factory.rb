module Stages
  # Turns a start/finish dispatch-table entry into a service: a callable is invoked with every collaborator
  # keyword, and a `[Klass, keys]` or `[Klass, keys, extras]` pair becomes
  # `Klass.new(**collaborators.merge(extras).slice(*keys))`.
  class CollaboratorFactory
    def initialize(collaborators)
      @collaborators = collaborators
    end

    def build(entry)
      return entry.call(**collaborators) if entry.respond_to?(:call)

      klass, keys, extras = entry
      klass.new(**collaborators.merge(extras || {}).slice(*keys))
    end

    private

    attr_reader :collaborators
  end
end
