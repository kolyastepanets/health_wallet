require "test_helper"

class LabImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "should get index" do
    get lab_imports_url
    assert_response :success
  end

  test "should get new" do
    get new_lab_import_url
    assert_response :success
  end

  test "create stores the file and enqueues an import job" do
    file = fixture_file_upload("John_Doe_HL7.txt", "text/plain")

    assert_difference -> { LabImport.count }, 1 do
      assert_enqueued_with(job: LabImportJob) do
        post lab_imports_url, params: { files: [ file ] }
      end
    end

    assert_redirected_to lab_imports_url
    import = LabImport.last
    assert_equal "John_Doe_HL7.txt", import.filename
    assert_includes import.content, "John Doe"
  end

  test "create without a file re-renders the form" do
    assert_no_difference -> { LabImport.count } do
      post lab_imports_url, params: { files: [ "" ] }
    end

    assert_response :unprocessable_entity
  end

  test "create rejects more than the allowed number of files" do
    files = Array.new(LabImportsController::MAX_FILES + 1) do
      fixture_file_upload("John_Doe_HL7.txt", "text/plain")
    end

    assert_no_difference -> { LabImport.count } do
      assert_no_enqueued_jobs do
        post lab_imports_url, params: { files: files }
      end
    end

    assert_response :unprocessable_entity
  end

  test "create rejects a file larger than the size limit" do
    big_file = Tempfile.new([ "big", ".txt" ])
    big_file.write("a" * (LabImportsController::MAX_FILE_SIZE + 1))
    big_file.rewind
    upload = Rack::Test::UploadedFile.new(big_file.path, "text/plain")

    assert_no_difference -> { LabImport.count } do
      assert_no_enqueued_jobs do
        post lab_imports_url, params: { files: [ upload ] }
      end
    end

    assert_response :unprocessable_entity
  ensure
    big_file&.close
    big_file&.unlink
  end

  test "create accepts several files and enqueues one job per file" do
    files = [
      fixture_file_upload("John_Doe_HL7.txt", "text/plain"),
      fixture_file_upload("Jane_Smith_HL7.txt", "text/plain")
    ]

    assert_difference -> { LabImport.count }, 2 do
      assert_enqueued_jobs 2, only: LabImportJob do
        post lab_imports_url, params: { files: files }
      end
    end

    assert_redirected_to lab_imports_url
    assert_equal ["Jane_Smith_HL7.txt", "John_Doe_HL7.txt"],
      LabImport.all.map(&:filename).sort
  end

  test "create ignores blank entries mixed in with a real file" do
    file = fixture_file_upload("John_Doe_HL7.txt", "text/plain")

    assert_difference -> { LabImport.count }, 1 do
      post lab_imports_url, params: { files: [ "", file, "" ] }
    end

    assert_redirected_to lab_imports_url
  end

  test "should show an import" do
    import = LabImport.create!(filename: "x.txt", content: "data", status: "completed",
                               result: { "patients_created" => 1 })

    get lab_import_url(import)
    assert_response :success
    assert_match "x.txt", response.body
  end
end
