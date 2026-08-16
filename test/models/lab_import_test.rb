require "test_helper"

class LabImportTest < ActiveSupport::TestCase
  test "defaults to pending status and empty result" do
    import = LabImport.create!(filename: "x.txt", content: "data")

    assert_equal "pending", import.status
    assert_equal({}, import.result)
    assert import.pending?
  end

  test "rejects an unknown status" do
    import = LabImport.new(filename: "x.txt", content: "data", status: "bogus")

    assert_not import.valid?
    assert_includes import.errors[:status], "is not included in the list"
  end

  test "status predicates reflect the status" do
    import = LabImport.new(status: "completed")

    assert import.completed?
    assert_not import.failed?
  end
end
