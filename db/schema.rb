# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_07_020000) do
  create_table "jira_syncs", force: :cascade do |t|
    t.boolean "auto_sync", default: false, null: false
    t.datetime "created_at", null: false
    t.string "jira_project"
    t.string "last_result"
    t.datetime "last_synced_at"
    t.string "parent_ticket"
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_jira_syncs_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_reviewers"
    t.text "default_skills"
    t.string "jira_assignee"
    t.string "jira_base_url"
    t.integer "kind", default: 0, null: false
    t.string "local_directory"
    t.string "name"
    t.string "repo_full_name"
    t.datetime "updated_at", null: false
  end

  create_table "prompt_templates", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "stage_type", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stage_runs", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.text "error"
    t.text "output"
    t.integer "stage_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stage_id"], name: "index_stage_runs_on_stage_id"
  end

  create_table "stages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "prompt"
    t.integer "prompt_template_id"
    t.integer "stage_type", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["prompt_template_id"], name: "index_stages_on_prompt_template_id"
    t.index ["workflow_id"], name: "index_stages_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.integer "ai_log_offset", default: 0, null: false
    t.string "ai_log_path"
    t.integer "ai_pid"
    t.datetime "ai_started_at"
    t.string "branch_name"
    t.datetime "created_at", null: false
    t.string "github_pr_url"
    t.string "github_reviewer"
    t.string "jira_ticket"
    t.integer "position", default: 0, null: false
    t.boolean "processing", default: false, null: false
    t.integer "project_id", null: false
    t.text "skills"
    t.integer "status", default: 0, null: false
    t.text "task_description"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_workflows_on_project_id"
  end

  add_foreign_key "jira_syncs", "projects"
  add_foreign_key "stage_runs", "stages"
  add_foreign_key "stages", "prompt_templates"
  add_foreign_key "stages", "workflows"
  add_foreign_key "workflows", "projects"
end
