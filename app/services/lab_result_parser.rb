class LabResultParser
  PatientBlock = Struct.new(:name, :dob, :sex_at_birth, :reference, :observations, keyword_init: true)
  ParsedObservation = Struct.new(:code, :value, :units, keyword_init: true)

  def self.parse(content)
    new(content).parse
  end

  def initialize(content)
    @content = content.to_s
  end

  def parse
    blocks = []
    current = nil

    @content.each_line do |raw|
      line = raw.strip
      next if line.empty?

      fields = line.split("|", -1).map(&:strip)

      case fields.length
      when 4
        current = build_header(fields)
        blocks << current if current
      when 3
        observation = build_observation(fields)
        current.observations << observation if current && observation
      end
    end

    blocks
  end

  private

  def build_header(fields)
    name, dob_str, sex_at_birth, reference = fields
    if name.empty? || reference.empty?
      Rails.logger.debug { "Skipped header row: missing name or reference" }
      return nil
    end

    dob = parse_date(dob_str)
    if dob.nil?
      Rails.logger.debug { "Skipped header row: unparseable date (reference=#{reference.inspect})" }
      return nil
    end

    PatientBlock.new(name: name, dob: dob, sex_at_birth: sex_at_birth, reference: reference, observations: [])
  end

  def build_observation(fields)
    code, result, units = fields
    value = parse_float(result)
    if code.empty? || value.nil? || units.blank?
      Rails.logger.debug do
        "Skipped observation row (code=#{code.inspect}, numeric_value=#{!value.nil?}, has_units=#{units.present?})"
      end
      return nil
    end

    ParsedObservation.new(code: code, value: value, units: units)
  end

  def parse_date(str)
    Date.iso8601(str)
  rescue ArgumentError, Date::Error
    nil
  end

  def parse_float(str)
    Float(str)
  rescue ArgumentError, TypeError
    nil
  end
end
