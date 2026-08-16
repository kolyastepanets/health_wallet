module LabImportsHelper
  def import_summary(lab_import)
    return "—" unless lab_import.completed?

    result = lab_import.result
    created = result.values_at("patients_created", "assessments_created", "observations_created").compact.sum
    updated = result["observations_updated"].to_i
    skipped = result["observations_skipped"].to_i

    parts = []
    parts << "#{created} created" if created.positive?
    parts << "#{updated} updated" if updated.positive?
    parts << "#{skipped} skipped" if skipped.positive?
    parts.presence&.join(", ") || "no changes"
  end
end
