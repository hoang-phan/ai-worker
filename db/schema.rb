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

ActiveRecord::Schema[8.1].define(version: 2026_10_23_100000) do
  create_table "bugsnag_syncs", force: :cascade do |t|
    t.boolean "auto_sync", default: false, null: false
    t.string "bugsnag_project", null: false
    t.datetime "created_at", null: false
    t.string "jira_project", null: false
    t.string "last_result"
    t.datetime "last_synced_at"
    t.json "ledger", default: {}, null: false
    t.integer "max_tickets", default: 3, null: false
    t.integer "min_events", default: 5, null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_bugsnag_syncs_on_project_id"
  end

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
    t.text "agent_lessons"
    t.boolean "brainstorm_auto_start", default: false, null: false
    t.boolean "brainstorm_enabled", default: false, null: false
    t.text "brainstorm_goal"
    t.string "brainstorm_last_result"
    t.datetime "brainstorm_last_run_at"
    t.integer "brainstorm_max_workflows", default: 5, null: false
    t.string "ci_command"
    t.text "ci_instructions"
    t.integer "ci_max_rounds", default: 5, null: false
    t.text "ci_verify_instructions"
    t.datetime "created_at", null: false
    t.text "default_pr_skills"
    t.string "default_reviewers"
    t.text "default_skills"
    t.integer "flow", default: 0, null: false
    t.string "jira_assignee"
    t.string "jira_base_url"
    t.string "jira_tester"
    t.integer "kind", default: 0, null: false
    t.string "local_directory"
    t.text "local_instructions"
    t.text "local_password"
    t.boolean "local_test_enabled", default: false, null: false
    t.string "local_url"
    t.string "local_username"
    t.string "name"
    t.text "pr_instructions"
    t.boolean "pr_stage_enabled", default: false, null: false
    t.string "repo_full_name"
    t.string "slack_last_result"
    t.datetime "slack_last_synced_at"
    t.string "slack_mention"
    t.string "slack_review_channel"
    t.boolean "slack_review_enabled", default: false, null: false
    t.text "slack_user_map"
    t.text "test_instructions"
    t.text "uat_instructions"
    t.text "uat_password"
    t.integer "uat_test_delay_minutes", default: 120, null: false
    t.boolean "uat_test_enabled", default: false, null: false
    t.string "uat_url"
    t.string "uat_username"
    t.datetime "updated_at", null: false
  end

  create_table "prompt_templates", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "effort"
    t.string "model"
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
    t.boolean "auto_advance", default: false, null: false
    t.string "channel"
    t.text "command"
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position"
    t.text "prompt"
    t.integer "prompt_template_id"
    t.integer "run_mode", default: 0, null: false
    t.integer "stage_type", null: false
    t.datetime "updated_at", null: false
    t.string "wait_for_workflow"
    t.integer "workflow_id", null: false
    t.index ["prompt_template_id"], name: "index_stages_on_prompt_template_id"
    t.index ["workflow_id"], name: "index_stages_on_workflow_id"
  end

  create_table "time_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "jira_worklog_id"
    t.integer "seconds", null: false
    t.datetime "started_at", null: false
    t.string "ticket_key", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id"
    t.index ["jira_worklog_id"], name: "index_time_logs_on_jira_worklog_id"
    t.index ["started_at"], name: "index_time_logs_on_started_at"
    t.index ["ticket_key"], name: "index_time_logs_on_ticket_key"
    t.index ["workflow_id"], name: "index_time_logs_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.integer "ai_log_offset", default: 0, null: false
    t.string "ai_log_path"
    t.integer "ai_pid"
    t.string "ai_provider"
    t.datetime "ai_started_at"
    t.boolean "auto_run", default: false, null: false
    t.boolean "awaiting_next", default: false, null: false
    t.string "branch_name"
    t.integer "ci_exit_status"
    t.string "ci_output_path"
    t.datetime "created_at", null: false
    t.integer "current_stage_id"
    t.string "github_pr_url"
    t.string "github_reviewer"
    t.datetime "jira_logged_synced_at"
    t.string "jira_ticket"
    t.integer "kind", default: 0, null: false
    t.text "local_test_feedback"
    t.integer "position", default: 0, null: false
    t.text "pr_skills"
    t.boolean "processing", default: false, null: false
    t.integer "project_id", null: false
    t.string "rotation_provider"
    t.text "skills"
    t.string "slack_review_thread_ts"
    t.string "slack_url"
    t.integer "status", default: 0, null: false
    t.string "summary"
    t.text "task_description"
    t.datetime "uat_test_at"
    t.datetime "updated_at", null: false
    t.json "variables"
    t.index ["project_id"], name: "index_workflows_on_project_id"
  end

  add_foreign_key "bugsnag_syncs", "projects"
  add_foreign_key "jira_syncs", "projects"
  add_foreign_key "stage_runs", "stages"
  add_foreign_key "stages", "prompt_templates"
  add_foreign_key "stages", "workflows"
  add_foreign_key "time_logs", "workflows"
  add_foreign_key "workflows", "projects"
end
