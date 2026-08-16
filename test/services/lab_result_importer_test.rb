require "test_helper"

class LabResultImporterTest < ActiveSupport::TestCase
  def import(fixture)
    blocks = LabResultParser.parse(file_fixture(fixture).read)
    LabResultImporter.new.import(blocks)
  end

  test "creates patient, assessment and catalog observations" do
    result = import("John_Doe_HL7.txt")

    assert_equal 1, result["patients_created"]
    assert_equal 1, result["assessments_created"]
    assert_equal 4, result["observations_created"]
    assert_equal 0, result["observations_updated"]
    assert_equal 0, result["observations_skipped"]

    patient = Patient.find_by(name: "John Doe")
    assert_equal Date.new(1985, 3, 15), patient.dob
    assert_equal "M", patient.sex_at_birth

    assessment = patient.assessments.find_by(reference: "REF-2024-001")
    systolic = assessment.observations.find_by(code: "8480-6")
    assert_equal "Blood Pressure (Systolic)", systolic.name
    assert_in_delta 120.0, systolic.value
    assert_equal "mmHg", systolic.units
  end

  test "re-importing the same file is idempotent" do
    import("John_Doe_HL7.txt")
    result = import("John_Doe_HL7.txt")

    assert_equal 1, Patient.count
    assert_equal 1, Patient.first.assessments.count
    assert_equal 4, Patient.first.assessments.first.observations.count

    assert_equal 0, result["patients_created"]
    assert_equal 0, result["assessments_created"]
    assert_equal 0, result["observations_created"]
    assert_equal 4, result["observations_updated"]
  end

  test "updates value and units of an existing observation" do
    import("John_Doe_HL7.txt")

    blocks = LabResultParser.parse("John Doe|1985-03-15|M|REF-2024-001\n8480-6|135|kPa\n")
    LabResultImporter.new.import(blocks)

    observation = Patient.find_by(name: "John Doe")
      .assessments.find_by(reference: "REF-2024-001")
      .observations.find_by(code: "8480-6")

    assert_in_delta 135.0, observation.value
    assert_equal "kPa", observation.units
  end

  test "skips observation codes outside the catalog" do
    result = import("Invalid_Rows_HL7.txt")

    assert_equal 1, result["observations_created"]
    assert_equal 1, result["observations_skipped"]

    assessment = Patient.find_by(name: "Alan Turing").assessments.first
    assert_equal ["8480-6"], assessment.observations.map(&:code)
  end

  test "imports several patients from one file" do
    result = import("Multiple_Patients_HL7.txt")

    assert_equal 3, result["patients_created"]
    assert_equal 3, result["assessments_created"]
    assert_equal 3, Patient.count
  end

  test "reuses an existing patient across files" do
    import("John_Doe_HL7.txt")
    result = import("Multiple_Patients_HL7.txt")

    assert_equal 3, Patient.count, "John Doe should be reused, not duplicated"
    assert_equal 2, result["patients_created"], "only Jane and Josh are new"
    assert_equal 2, Patient.find_by(name: "John Doe").assessments.count
  end

  def import_content(content)
    LabResultImporter.new.import(LabResultParser.parse(content))
  end

  test "returns zero counts and creates nothing for empty blocks" do
    result = LabResultImporter.new.import([])

    assert_equal 0, Patient.count
    LabResultImporter::COUNT_KEYS.each do |key|
      assert_equal 0, result[key.to_s], "#{key} should be zero"
    end
  end

  test "creates a patient and assessment even with no observations" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n")

    assert_equal 1, result["patients_created"]
    assert_equal 1, result["assessments_created"]
    assert_equal 0, result["observations_created"]
    assert_equal 0, Patient.find_by(name: "John Doe").assessments.first.observations.count
  end

  test "a repeated code within one file is created once then updated" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n8480-6|120|mmHg\n8480-6|130|mmHg\n")

    assert_equal 1, result["observations_created"]
    assert_equal 1, result["observations_updated"]

    observations = Patient.find_by(name: "John Doe").assessments.first.observations
    assert_equal 1, observations.count, "the same code must not be duplicated"
    assert_in_delta 130.0, observations.first.value, 0.001
  end

  test "same patient with two references creates two assessments" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|72|bpm\n" \
              "John Doe|1985-03-15|M|REF-2\n8867-4|80|bpm\n"
    result = import_content(content)

    assert_equal 1, result["patients_created"]
    assert_equal 2, result["assessments_created"]
    assert_equal 2, Patient.find_by(name: "John Doe").assessments.count
  end

  test "a file whose codes are all outside the catalog creates no observations" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n0000-0|1|x\n1111-1|2|y\n")

    assert_equal 1, result["patients_created"]
    assert_equal 1, result["assessments_created"]
    assert_equal 0, result["observations_created"]
    assert_equal 2, result["observations_skipped"]
  end

  test "stores a Celsius temperature verbatim without converting" do
    import_content("John Doe|1985-03-15|M|REF-1\n8310-5|37.0|°C\n")

    observation = Patient.find_by(name: "John Doe")
      .assessments.first
      .observations.find_by(code: "8310-5")

    assert_equal "Body Temperature", observation.name
    assert_in_delta 37.0, observation.value, 0.001
    assert_equal "°C", observation.units, "units must be stored as sent, no C-to-F conversion"
  end

  test "stores Fahrenheit and Celsius side by side, each untouched" do
    import_content("John Doe|1985-03-15|M|REF-1\n8310-5|98.6|°F\n" \
                   "Jane Roe|1990-07-22|F|REF-2\n8310-5|37.0|°C\n")

    john = Patient.find_by(name: "John Doe").assessments.first.observations.find_by(code: "8310-5")
    jane = Patient.find_by(name: "Jane Roe").assessments.first.observations.find_by(code: "8310-5")

    assert_equal "°F", john.units
    assert_in_delta 98.6, john.value, 0.001
    assert_equal "°C", jane.units
    assert_in_delta 37.0, jane.value, 0.001
  end

  test "does not import an observation whose value is empty" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n8867-4||bpm\n")

    assert_equal 0, result["observations_created"]
    assert_equal 0, Patient.find_by(name: "John Doe").assessments.first.observations.count
  end

  test "does not import an observation whose value is non-numeric" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n8867-4|high|bpm\n")

    assert_equal 0, result["observations_created"]
    assert_equal 0, Patient.find_by(name: "John Doe").assessments.first.observations.count
  end

  # Characterization test of a known limitation: patient matching is case-sensitive,
  # so a name that differs only in case is treated as a different person. Accepted
  # trade-off given the fixed file format has no stable patient ID (MRN/PID).
  test "differing name case creates two distinct patients" do
    result = import_content("john doe|1985-03-15|M|REF-1\n8867-4|72|bpm\n" \
                            "John Doe|1985-03-15|M|REF-2\n8867-4|80|bpm\n")

    assert_equal 2, result["patients_created"],
      "'john doe' and 'John Doe' are matched case-sensitively, so they are two patients"
    assert_equal 2, Patient.count
    assert_equal ["John Doe", "john doe"], Patient.all.map(&:name).sort
  end

  test "identical name case is deduplicated into one patient" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n8867-4|72|bpm\n" \
                            "John Doe|1985-03-15|M|REF-2\n8867-4|80|bpm\n")

    assert_equal 1, result["patients_created"], "same name+dob+sex is one patient"
    assert_equal 1, Patient.count
    assert_equal 2, Patient.first.assessments.count, "but two assessments, one per reference"
  end

  test "same name and dob but different sex are two patients" do
    result = import_content("John Doe|1985-03-15|M|REF-1\n8867-4|72|bpm\n" \
                            "John Doe|1985-03-15|F|REF-2\n8867-4|80|bpm\n")

    assert_equal 2, result["patients_created"], "sex_at_birth is part of patient identity"
    assert_equal 2, Patient.count
  end

  test "two blocks for the same patient and reference merge into one assessment" do
    content = "John Doe|1985-03-15|M|REF-1\n8480-6|120|mmHg\n" \
              "John Doe|1985-03-15|M|REF-1\n8867-4|72|bpm\n"
    result = import_content(content)

    assert_equal 1, result["patients_created"]
    assert_equal 1, result["assessments_created"], "same patient+reference is one assessment"
    assert_equal 2, result["observations_created"]

    assessment = Patient.find_by(name: "John Doe").assessments.first
    assert_equal 1, Patient.find_by(name: "John Doe").assessments.count
    assert_equal ["8480-6", "8867-4"], assessment.observations.map(&:code).sort,
      "observations from both blocks land on the same assessment"
  end

  test "stores an observation whose value is exactly zero" do
    import_content("John Doe|1985-03-15|M|REF-1\n8867-4|0|bpm\n")

    observation = Patient.find_by(name: "John Doe").assessments.first.observations.find_by(code: "8867-4")
    assert_in_delta 0.0, observation.value, 0.001
  end
end
