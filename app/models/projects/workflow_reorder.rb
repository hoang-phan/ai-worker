module Projects
  # Moves a workflow up or down the project's priority list (the scheduler works through workflows by position).
  class WorkflowReorder
    def initialize(project)
      @project = project
    end

    # Swaps `workflow` with its neighbour in the position order (`:up` = earlier = higher priority). Renumbers the
    # whole list 1..n so duplicate positions can't make the move a no-op. Returns false when already at that end
    # or when the workflow isn't in the project.
    def move(workflow, direction)
      ordered = @project.workflows.order(:position, :id).to_a
      index = ordered.index(workflow)
      return false if index.nil?

      target = direction.to_s == "up" ? index - 1 : index + 1
      return false if target.negative? || target >= ordered.size

      ordered[index], ordered[target] = ordered[target], ordered[index]
      @project.transaction { ordered.each.with_index(1) { |w, position| w.update_columns(position: position) unless w.position == position } }
      true
    end
  end
end
