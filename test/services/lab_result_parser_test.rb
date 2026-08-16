require "test_helper"

class LabResultParserTest < ActiveSupport::TestCase
  test "parses a single patient block with its observations" do
    blocks = LabResultParser.parse(file_fixture("John_Doe_HL7.txt").read)

    assert_equal 1, blocks.size
    block = blocks.first
    assert_equal "John Doe", block.name
    assert_equal Date.new(1985, 3, 15), block.dob
    assert_equal "M", block.sex_at_birth
    assert_equal "REF-2024-001", block.reference

    assert_equal 4, block.observations.size
    first = block.observations.first
    assert_equal "8480-6", first.code
    assert_in_delta 120.0, first.value
    assert_equal "mmHg", first.units
  end

  test "splits multiple patient blocks by the header line" do
    blocks = LabResultParser.parse(file_fixture("Multiple_Patients_HL7.txt").read)

    assert_equal 3, blocks.size, "expected three blocks"
    assert_equal ["John Doe", "Jane Smith", "Josh Brown"], blocks.map(&:name)
    assert_equal 1, blocks.first.observations.size
    assert_equal 2, blocks.last.observations.size
  end

  test "drops non-numeric observation rows but keeps valid ones" do
    blocks = LabResultParser.parse(file_fixture("Invalid_Rows_HL7.txt").read)

    codes = blocks.first.observations.map(&:code)
    assert_equal ["8480-6", "9999-9"], codes, "non-numeric row should be dropped"
  end

  test "ignores blank lines and tolerates CRLF" do
    content = "\r\nJohn Doe|1985-03-15|M|REF-1\r\n\r\n8867-4|72|bpm\r\n"

    blocks = LabResultParser.parse(content)

    assert_equal 1, blocks.size
    assert_equal 1, blocks.first.observations.size
  end

  test "skips a block whose header has an invalid date" do
    content = "Bad Date|not-a-date|M|REF-1\n8867-4|72|bpm\n"

    assert_empty LabResultParser.parse(content)
  end

  test "returns no blocks for blank content" do
    assert_empty LabResultParser.parse("")
    assert_empty LabResultParser.parse(nil)
  end

  test "ignores an observation that appears before any patient header" do
    content = "8867-4|72|bpm\nJohn Doe|1985-03-15|M|REF-1\n8480-6|120|mmHg\n"

    blocks = LabResultParser.parse(content)

    assert_equal 1, blocks.size
    assert_equal ["8480-6"], blocks.first.observations.map(&:code),
      "the orphan row before the header should be dropped"
  end

  test "skips a header whose name is blank" do
    content = "|1985-03-15|M|REF-1\n8867-4|72|bpm\n"

    assert_empty LabResultParser.parse(content)
  end

  test "ignores lines that do not have three or four fields" do
    content = "John Doe|1985-03-15|M|REF-1\n" \
              "only|two\n" \
              "a|b|c|d|e\n" \
              "8867-4|72|bpm\n"

    blocks = LabResultParser.parse(content)

    assert_equal 1, blocks.size
    assert_equal ["8867-4"], blocks.first.observations.map(&:code)
  end

  test "parses negative and decimal observation values" do
    content = "John Doe|1985-03-15|M|REF-1\n8310-5|-0.5|C\n8867-4|72.5|bpm\n"

    observations = LabResultParser.parse(content).first.observations

    assert_in_delta(-0.5, observations[0].value)
    assert_in_delta 72.5, observations[1].value
  end

  test "drops a reading whose units are empty" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|72|\n"

    assert_empty LabResultParser.parse(content).first.observations,
      "a reading with empty units must be skipped"
  end

  test "drops a reading whose units are blank whitespace" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|72|   \n"

    assert_empty LabResultParser.parse(content).first.observations,
      "whitespace-only units must be treated as empty"
  end

  test "drops a reading whose value is missing" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4||bpm\n"

    assert_empty LabResultParser.parse(content).first.observations,
      "a row without a numeric value must be skipped"
  end

  test "drops a reading whose value is non-numeric text" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|high|bpm\n"

    assert_empty LabResultParser.parse(content).first.observations,
      "a non-numeric value must be skipped"
  end

  test "keeps temperature units verbatim for both Celsius and Fahrenheit" do
    content = "John Doe|1985-03-15|M|REF-1\n8310-5|37.0|°C\n8310-5|98.6|°F\n"

    observations = LabResultParser.parse(content).first.observations

    assert_equal ["°C", "°F"], observations.map(&:units), "units must be kept exactly as sent"
    assert_in_delta 37.0, observations[0].value
    assert_in_delta 98.6, observations[1].value
  end

  test "skips a header whose reference is blank" do
    content = "John Doe|1985-03-15|M|\n8867-4|72|bpm\n"

    assert_empty LabResultParser.parse(content),
      "a header with no reference must be dropped"
  end

  test "skips an observation whose code is blank" do
    content = "John Doe|1985-03-15|M|REF-1\n|72|bpm\n"

    assert_empty LabResultParser.parse(content).first.observations,
      "an observation with no code must be dropped"
  end

  test "keeps a reading whose value is exactly zero" do
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|0|bpm\n"

    observations = LabResultParser.parse(content).first.observations

    assert_equal 1, observations.size, "zero is a valid numeric value, not missing"
    assert_in_delta 0.0, observations.first.value
  end

  test "parses a header even when the sex field is empty" do
    content = "John Doe|1985-03-15||REF-1\n8867-4|72|bpm\n"

    block = LabResultParser.parse(content).first

    assert_equal "John Doe", block.name
    assert_equal "", block.sex_at_birth, "sex is optional at parse time and kept as an empty string"
    assert_equal 1, block.observations.size
  end

  test "trims surrounding whitespace from every field" do
    content = "  John Doe  | 1985-03-15 | M | REF-1 \n 8867-4 | 72 | bpm \n"

    block = LabResultParser.parse(content).first

    assert_equal "John Doe", block.name
    assert_equal "REF-1", block.reference
    assert_equal "8867-4", block.observations.first.code
    assert_in_delta 72.0, block.observations.first.value
    assert_equal "bpm", block.observations.first.units
  end

  test "a trailing pipe turns an observation into a dropped four-field row" do
    # "8867-4|72|bpm|" splits into four fields, so it is treated as a (broken)
    # header rather than an observation, and dropped for having no reference.
    content = "John Doe|1985-03-15|M|REF-1\n8867-4|72|bpm|\n"

    block = LabResultParser.parse(content).first

    assert_empty block.observations, "a four-field row is never treated as an observation"
  end
end
