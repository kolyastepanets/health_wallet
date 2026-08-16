class Patient
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :dob, type: Date
  field :sex_at_birth, type: String

  index({ name: 1, dob: 1, sex_at_birth: 1 }, { unique: true })

  has_many :assessments
end
