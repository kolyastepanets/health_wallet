class LabImport
  include Mongoid::Document
  include Mongoid::Timestamps

  STATUSES = ["pending", "processing", "completed", "failed"].freeze

  field :filename,      type: String
  field :content,       type: String
  field :status,        type: String, default: "pending"
  field :error_message, type: String
  field :result,        type: Hash, default: {}

  validates :status, inclusion: { in: STATUSES }

  STATUSES.each do |state|
    define_method("#{state}?") { status == state }
  end
end
