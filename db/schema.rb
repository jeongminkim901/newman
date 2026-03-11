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

ActiveRecord::Schema[8.1].define(version: 2026_03_11_001000) do
  create_table "runs", force: :cascade do |t|
    t.string "collection_path", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "environment_path"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.text "input_vars_json"
    t.string "name"
    t.datetime "queued_at"
    t.string "report_html_path"
    t.string "report_json_path"
    t.string "run_mode", default: "sync", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.text "stderr"
    t.text "stdout"
    t.datetime "updated_at", null: false
  end
end
