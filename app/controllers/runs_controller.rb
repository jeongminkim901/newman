class RunsController < ApplicationController
  require "open3"
  require "json"
  require "fileutils"

  def index
    @runs = Run.order(created_at: :desc)
  end

  def new
    @run = Run.new
  end

  def create
    async = params.dig(:run, :async) == "1"
    collection_file = params.dig(:run, :collection_file)

    @run = Run.new(
      name: params.dig(:run, :name),
      status: "queued",
      run_mode: async ? "async" : "sync"
    )

    if collection_file.blank?
      @run.errors.add(:collection_path, "collection file is required")
      return render :new, status: :unprocessable_entity
    end

    @run.save!

    run_dir = Rails.root.join("storage", "runs", @run.id.to_s)
    FileUtils.mkdir_p(run_dir)

    collection_path = run_dir.join("collection.json")
    File.binwrite(collection_path, collection_file.read)

    environment_path = nil
    env_file = params.dig(:run, :environment_file)
    if env_file.present?
      environment_path = run_dir.join("environment.json")
      File.binwrite(environment_path, env_file.read)
    end

    vars = build_env_vars(
      params.dig(:run, :ip),
      params.dig(:run, :token),
      params.dig(:run, :extra_vars_json)
    )

    report_json_path = run_dir.join("report.json")
    report_html_path = run_dir.join("report.html")

    @run.update!(
      collection_path: collection_path.to_s,
      environment_path: environment_path&.to_s,
      input_vars_json: vars.any? ? vars.to_json : nil,
      report_json_path: report_json_path.to_s,
      report_html_path: report_html_path.to_s,
      queued_at: async ? Time.current : nil
    )

    if async
      RunNewmanJob.perform_later(@run.id)
      redirect_to run_path(@run), notice: "Run queued"
    else
      NewmanRunService.execute!(@run)
      redirect_to run_path(@run)
    end
  rescue JSON::ParserError => e
    @run.errors.add(:input_vars_json, "invalid JSON: #{e.message}")
    render :new, status: :unprocessable_entity
  rescue => e
    @run.status = "failed" if @run&.persisted?
    @run.stderr = [@run.stderr, e.class.name, e.message].compact.join("\n") if @run
    @run.finished_at = Time.current if @run
    @run.save! if @run&.persisted?
    raise
  end

  def show
    @run = Run.find(params[:id])
  end

  def report
    @run = Run.find(params[:id])
    kind = params[:kind]
    path = case kind
    when "json" then @run.report_json_path
    when "html" then @run.report_html_path
    else nil
    end

    if path.present? && File.exist?(path)
      send_file path, disposition: "inline"
    else
      redirect_to run_path(@run), alert: "Report not found"
    end
  end

  private

  def build_env_vars(ip, token, extra_vars_json)
    vars = []
    vars << { "key" => "ip", "value" => ip.to_s, "enabled" => true } if ip.present?
    vars << { "key" => "token", "value" => token.to_s, "enabled" => true } if token.present?

    return vars if extra_vars_json.blank?

    parsed = JSON.parse(extra_vars_json)
    if parsed.is_a?(Array)
      parsed.each do |item|
        next unless item.is_a?(Hash)
        key = item["key"] || item[:key]
        value = item["value"] || item[:value]
        next if key.nil?
        vars << { "key" => key.to_s, "value" => value.to_s, "enabled" => true }
      end
    elsif parsed.is_a?(Hash)
      parsed.each do |key, value|
        vars << { "key" => key.to_s, "value" => value.to_s, "enabled" => true }
      end
    else
      raise JSON::ParserError, "extra_vars_json must be an object or array"
    end

    vars
  end
end
