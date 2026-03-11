class AddReportAndLogTextToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :report_json_text, :text
    add_column :runs, :report_html_text, :text
    add_column :runs, :log_text, :text
  end
end
