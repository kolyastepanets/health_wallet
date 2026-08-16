class LabResultImporter
  COUNT_KEYS = [
    :patients_created,
    :assessments_created,
    :observations_created,
    :observations_updated,
    :observations_skipped
  ].freeze

  def import(blocks)
    @counts = COUNT_KEYS.index_with { 0 }
    @skipped_codes = Hash.new(0)

    blocks.each do |block|
      patient = find_or_create_patient(block)
      assessment = find_or_create_assessment(patient, block)
      block.observations.each { |observation| import_observation(assessment, observation) }
    end

    log_skipped_codes
    @counts.transform_keys(&:to_s)
  end

  private

  def find_or_create_patient(block)
    attrs = { name: block.name, dob: block.dob, sex_at_birth: block.sex_at_birth }
    existing = Patient.where(attrs).first
    return existing if existing

    @counts[:patients_created] += 1
    Patient.create!(attrs)
  rescue Mongo::Error::OperationFailure => e
    raise unless duplicate_key?(e)

    @counts[:patients_created] -= 1
    Patient.where(attrs).first
  end

  def find_or_create_assessment(patient, block)
    existing = patient.assessments.where(reference: block.reference).first
    return existing if existing

    @counts[:assessments_created] += 1
    patient.assessments.create!(reference: block.reference)
  rescue Mongo::Error::OperationFailure => e
    raise unless duplicate_key?(e)

    @counts[:assessments_created] -= 1
    patient.assessments.where(reference: block.reference).first
  end

  def import_observation(assessment, observation)
    unless LoincCatalog.allowed?(observation.code)
      @counts[:observations_skipped] += 1
      @skipped_codes[observation.code] += 1
      return
    end

    existing = assessment.observations.detect { |o| o.code == observation.code }

    if existing
      existing.update!(value: observation.value, units: observation.units)
      @counts[:observations_updated] += 1
      return
    end

    assessment.observations.create!(
      code:  observation.code,
      name:  LoincCatalog.name_for(observation.code),
      value: observation.value,
      units: observation.units
    )
    @counts[:observations_created] += 1
  end

  def log_skipped_codes
    return if @skipped_codes.empty?

    breakdown = @skipped_codes.map { |code, count| "#{code}=#{count}" }.join(", ")
    Rails.logger.warn("Skipped #{@counts[:observations_skipped]} observation(s) with non-catalog codes: #{breakdown}")
  end

  def duplicate_key?(error)
    error.message.include?("E11000")
  end
end
