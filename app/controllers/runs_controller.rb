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

    @run = Run.new

    if collection_file.blank?
      @run.errors.add(:collection_path, "collection file is required")
      return render :new, status: :unprocessable_entity
    end

    @run = Run.create!(
      name: params.dig(:run, :name),
      status: "queued",
      run_mode: async ? "async" : "sync",
      collection_path: "pending"
    )

    run_id = @run.id.to_i
    run_dir = run_dir_for_id(run_id)
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
    @run.stderr = [ @run.stderr, e.class.name, e.message ].compact.join("\n") if @run
    @run.finished_at = Time.current if @run
    @run.save! if @run&.persisted?
    raise
  end

  def show
    @run = Run.find(params[:id].to_i)
    @report = load_report(@run.report_json_text)
    @executions = build_executions(@report)
    @stats = build_stats(@executions)
    @failed_executions = @executions.select { |ex| ex[:failed] || ex[:error].present? }
  end

  def report
    @run = Run.find(params[:id].to_i)
    kind = params[:kind].to_s
    unless %w[json html].include?(kind)
      return redirect_to run_path(@run), alert: "Report not found"
    end

    data = report_data_for(@run, kind)
    if data.present?
      content_type = kind == "json" ? "application/json" : "text/html"
      send_data data, type: content_type, disposition: "inline"
    else
      redirect_to run_path(@run), alert: "Report not found"
    end
  end

  def stream
    @run = Run.find(params[:id].to_i)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    last_len = 0

    begin
      loop do
        @run.reload
        log_text = @run.log_text.to_s
        if log_text.length > last_len
          chunk = log_text[last_len..]
          chunk.to_s.each_line do |line|
            response.stream.write("data: #{line.rstrip}\n\n")
          end
          last_len = log_text.length
        end

        break unless @run.status.in?(%w[queued running])
        sleep 0.8
      end
    rescue => e
      response.stream.write("event: error\ndata: #{e.message}\n\n")
    ensure
      response.stream.close
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

  def load_report(path)
    return nil if path.blank? || !File.exist?(path)
    JSON.parse(File.read(path))
  rescue
    nil
  end

  def build_executions(report)
    return [] unless report.is_a?(Hash)

    executions = report.dig("run", "executions") || []
    executions.map do |ex|
      response = ex["response"] || {}
      code = response["code"]
      method = ex.dig("item", "request", "method")
      url = ex.dig("item", "request", "url", "raw") || ex.dig("item", "request", "url")
      name = ex.dig("item", "name")
      time_ms = response["responseTime"]
      failed = (ex["assertions"] || []).any? { |a| a["error"].present? }
      error = ex["error"]&.dig("message")

      {
        name: name,
        method: method,
        url: url,
        status: code,
        time_ms: time_ms,
        failed: failed,
        error: error,
        status_group: code ? (code / 100) : nil
      }
    end
  end

  def build_stats(executions)
    total = executions.length
    failed = executions.count { |e| e[:failed] || e[:error].present? }
    groups = executions.group_by { |e| e[:status_group] }
    {
      total: total,
      failed: failed,
      ok: groups[2]&.length.to_i,
      redirect: groups[3]&.length.to_i,
      client_error: groups[4]&.length.to_i,
      server_error: groups[5]&.length.to_i
    }
  end

  def run_dir_for_id(run_id)
    Rails.root.join("storage", "runs", run_id.to_i.to_s)
  end

  def report_path_for_id(run_id, kind)
    kind = kind.to_s
    return nil unless %w[json html].include?(kind)

    file_name = case kind
    when "json" then "report.json"
    when "html" then "report.html"
    else nil
    end
    return nil if file_name.nil?

    run_dir_for_id(run_id).join(file_name).to_s
  end

  def log_path_for_id(run_id)
    run_dir_for_id(run_id).join("run.log").to_s
  end

  def report_data_for(run, kind)
    if kind == "json"
      run.report_json_text.to_s.presence
    else
      run.report_html_text.to_s.presence
    end
  end
end
