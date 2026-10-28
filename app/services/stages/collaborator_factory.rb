module Stages
  # Turns a start/finish dispatch-table entry into a service: a callable is invoked with every collaborator
  # keyword, and a `[Klass, keys]` pair becomes `Klass.new(**collaborators.slice(*keys))`.
  class CollaboratorFactory
    def initialize(collaborators)
      @collaborators = collaborators
    end

    def build(entry)
      return entry.call(**collaborators) if entry.respond_to?(:call)

      klass, keys = entry
      klass.new(**collaborators.slice(*keys))
    end

    private

    attr_reader :collaborators
  end
end
