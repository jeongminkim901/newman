class AddLogPathToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :log_path, :string
  end
end
