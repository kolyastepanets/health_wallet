class LabImportJob < ApplicationJob
  queue_as :default

  def perform(lab_import_id)
    lab_import = LabImport.find(lab_import_id)

    Rails.logger.tagged("LabImport", lab_import_id) do
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      lab_import.update!(status: "processing")
      Rails.logger.info(
        "Import started (filename=#{lab_import.filename.inspect}, " \
        "bytes=#{lab_import.content.to_s.bytesize})"
      )

      blocks = LabResultParser.parse(lab_import.content)
      observation_count = blocks.sum { |block| block.observations.size }
      Rails.logger.info("Parsed #{blocks.size} patient block(s), #{observation_count} observation(s)")

      result = LabResultImporter.new.import(blocks)

      lab_import.update!(status: "completed", result: result, error_message: nil)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      summary = result.map { |key, value| "#{key}=#{value}" }.join(", ")
      Rails.logger.info("Import completed in #{duration.round(3)}s (#{summary})")
    end
  rescue StandardError => e
    Rails.logger.tagged("LabImport", lab_import_id) do
      Rails.logger.error("Import failed: #{e.class}: #{e.message}")
    end
    lab_import&.update(status: "failed", error_message: e.message)
    raise
  end
end
