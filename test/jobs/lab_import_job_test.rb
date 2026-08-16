require "test_helper"
require "minitest/mock"

class LabImportJobTest < ActiveSupport::TestCase
  test "processes a valid file and marks the import completed" do
    import = LabImport.create!(
      filename: "John_Doe_HL7.txt",
      content: file_fixture("John_Doe_HL7.txt").read
    )

    LabImportJob.perform_now(import.id.to_s)

    import.reload
    assert_equal "completed", import.status
    assert_nil import.error_message
    assert_equal 1, import.result["patients_created"]
    assert_equal 4, import.result["observations_created"]

    assert_equal 1, Patient.where(name: "John Doe").count
  end

  test "marks the import failed and re-raises on a fatal error" do
    import = LabImport.create!(filename: "x.txt", content: "data")

    LabResultParser.stub(:parse, ->(_) { raise "boom" }) do
      assert_raises(RuntimeError) { LabImportJob.perform_now(import.id.to_s) }
    end

    import.reload
    assert_equal "failed", import.status
    assert_equal "boom", import.error_message
  end

  test "completes with zero counts when the file has no valid blocks" do
    import = LabImport.create!(filename: "empty.txt", content: "garbage without pipes\n")

    LabImportJob.perform_now(import.id.to_s)

    import.reload
    assert_equal "completed", import.status
    assert_nil import.error_message
    assert_equal 0, import.result["patients_created"]
    assert_equal 0, Patient.count
  end

  test "raises when the import record does not exist" do
    assert_raises(Mongoid::Errors::DocumentNotFound) do
      LabImportJob.perform_now("000000000000000000000000")
    end
  end

  test "clears a stale error_message when a later run succeeds" do
    import = LabImport.create!(
      filename: "John_Doe_HL7.txt",
      content: file_fixture("John_Doe_HL7.txt").read,
      status: "failed",
      error_message: "previous failure"
    )

    LabImportJob.perform_now(import.id.to_s)

    import.reload
    assert_equal "completed", import.status
    assert_nil import.error_message, "a successful run must clear the previous error"
  end

  test "records the count breakdown in the result hash" do
    import = LabImport.create!(
      filename: "Invalid_Rows_HL7.txt",
      content: file_fixture("Invalid_Rows_HL7.txt").read
    )

    LabImportJob.perform_now(import.id.to_s)

    import.reload
    assert_equal 1, import.result["observations_created"]
    assert_equal 1, import.result["observations_skipped"]
  end
end
