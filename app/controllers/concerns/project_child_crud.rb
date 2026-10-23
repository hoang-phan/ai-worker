# Shared CRUD actions for project-owned records. Include this after ProjectScoped
# so @project is available before the child record is loaded.
module ProjectChildCrud
  extend ActiveSupport::Concern

  included do
    before_action :set_project_child, only: %i[edit update destroy]
  end

  class_methods do
    attr_reader :project_child_association, :project_child_flash_label

    def project_child_crud(association:, flash_label:)
      @project_child_association = association
      @project_child_flash_label = flash_label
    end
  end

  def new
    set_project_child_instance(@project.public_send(project_child_association).new)
  end

  def edit
  end

  def create
    set_project_child_instance(@project.public_send(project_child_association).new(project_child_params))
    if project_child.save
      redirect_to @project, notice: "#{project_child_flash_label} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if project_child.update(project_child_params)
      redirect_to @project, notice: "#{project_child_flash_label} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project_child.destroy
    redirect_to @project, notice: "#{project_child_flash_label} deleted."
  end

  private

  def project_child_association
    self.class.project_child_association
  end

  def project_child_flash_label
    self.class.project_child_flash_label
  end

  def set_project_child
    set_project_child_instance(@project.public_send(project_child_association).find(params[:id]))
  end

  def project_child
    instance_variable_get(project_child_instance_variable)
  end

  def set_project_child_instance(record)
    instance_variable_set(project_child_instance_variable, record)
  end

  def project_child_instance_variable
    "@#{project_child_name}"
  end

  def project_child_name
    project_child_association.to_s.singularize
  end

  def project_child_params
    send("#{project_child_name}_params")
  end
end
