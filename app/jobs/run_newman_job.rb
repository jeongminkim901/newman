class RunNewmanJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = Run.find(run_id)
    NewmanRunService.execute!(run)
  end
end
