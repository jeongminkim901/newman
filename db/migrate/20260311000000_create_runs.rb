class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.string :name
      t.string :status, null: false, default: "queued"
      t.string :collection_path, null: false
      t.string :environment_path
      t.text :input_vars_json
      t.string :report_json_path
      t.string :report_html_path
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.integer :exit_code
      t.text :stdout
      t.text :stderr
      t.timestamps
    end
  end
end
