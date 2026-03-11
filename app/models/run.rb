class Run < ApplicationRecord
  STATUSES = %w[queued running success failed].freeze
  RUN_MODES = %w[sync async].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :collection_path, presence: true
  validates :run_mode, presence: true, inclusion: { in: RUN_MODES }
end
