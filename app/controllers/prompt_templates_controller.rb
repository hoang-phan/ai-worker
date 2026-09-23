class PromptTemplatesController < ApplicationController
  before_action :set_prompt_template, only: %i[show edit update destroy]

  def index
    @prompt_templates = PromptTemplate.order(:stage_type, :name)
  end

  def show
  end

  def new
    @prompt_template = PromptTemplate.new
  end

  def edit
  end

  def create
    @prompt_template = PromptTemplate.new(prompt_template_params)
    if @prompt_template.save
      redirect_to @prompt_template, notice: "Template created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @prompt_template.update(prompt_template_params)
      redirect_to @prompt_template, notice: "Template updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @prompt_template.destroy
    redirect_to prompt_templates_path, notice: "Template deleted."
  end

  private

  def set_prompt_template
    @prompt_template = PromptTemplate.find(params[:id])
  end

  def prompt_template_params
    params.require(:prompt_template).permit(:name, :stage_type, :body, :active)
  end
end
