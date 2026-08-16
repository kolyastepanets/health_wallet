class LabImportsController < ApplicationController
  MAX_FILES = 20
  MAX_FILE_SIZE = 1.megabyte

  def index
    page = params[:page].to_i
    page = 1 if page < 1

    @lab_imports = LabImport.all.order(created_at: :desc).skip((page - 1) * 10).limit(10)
    @total_count = LabImport.count
    @current_page = page
    @total_pages = (@total_count / 10.0).ceil
  end

  def show
    @lab_import = LabImport.find(params[:id])
  end

  def new
  end

  def create
    files = Array(params[:files]).select { |file| file.respond_to?(:read) }

    if files.empty?
      Rails.logger.warn("LabImport upload rejected: no readable files in request")
      flash.now[:alert] = "Please choose at least one file to upload."
      return render :new, status: :unprocessable_entity
    end

    if files.size > MAX_FILES
      Rails.logger.warn("LabImport upload rejected: #{files.size} files exceeds MAX_FILES=#{MAX_FILES}")
      flash.now[:alert] = "You can upload at most #{MAX_FILES} files at once."
      return render :new, status: :unprocessable_entity
    end

    oversized = files.select { |file| file.size > MAX_FILE_SIZE }
    if oversized.any?
      names = oversized.map(&:original_filename).join(", ")
      Rails.logger.warn("LabImport upload rejected: files over #{MAX_FILE_SIZE} bytes: #{names}")
      flash.now[:alert] = "Each file must be #{MAX_FILE_SIZE / 1.megabyte} MB or smaller. Too large: #{names}."
      return render :new, status: :unprocessable_entity
    end

    files.each do |file|
      content = file.read.to_s.force_encoding(Encoding::UTF_8)
      lab_import = LabImport.create!(filename: file.original_filename, content: content)
      LabImportJob.perform_later(lab_import.id.to_s)
      Rails.logger.info(
        "LabImport enqueued (id=#{lab_import.id}, filename=#{file.original_filename.inspect}, " \
        "bytes=#{content.bytesize})"
      )
    end

    Rails.logger.info("LabImport batch accepted: #{files.size} file(s) enqueued")
    redirect_to lab_imports_path,
      notice: "#{files.size} file#{'s' if files.size != 1} uploaded. Import started."
  end
end
