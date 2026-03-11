class AddRunModeToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :run_mode, :string, null: false, default: "sync"
    add_column :runs, :queued_at, :datetime
  end
end
