class NewmanRunService
  require "open3"
  require "json"
  require "fileutils"

  LOG_BUFFER_LIMIT = 20000

  def self.execute!(run)
    new(run).execute!
  end

  def initialize(run)
    @run = run
  end

  def execute!
    run_dir = Rails.root.join("storage", "runs", @run.id.to_i.to_s)
    FileUtils.mkdir_p(run_dir)

    collection_path = @run.collection_path || run_dir.join("collection.json").to_s
    environment_path = @run.environment_path

    report_json_path = @run.report_json_path || run_dir.join("report.json").to_s
    report_html_path = @run.report_html_path || run_dir.join("report.html").to_s

    log_path = @run.log_path || run_dir.join("run.log").to_s

    vars_path = nil
    if @run.input_vars_json.present?
      vars = normalize_vars(JSON.parse(@run.input_vars_json))
      if vars.any?
        vars_path = run_dir.join("vars.json")
        File.write(vars_path, JSON.pretty_generate(vars))
      end
    end

    if Gem.win_platform?
      ENV["PATH"] = "C:\\Program Files\\nodejs;#{ENV['PATH']}"
    end

    @run.update!(
      status: "running",
      started_at: Time.current,
      log_path: log_path,
      report_json_path: report_json_path.to_s,
      report_html_path: report_html_path.to_s
    )

    cmd = [
      "node",
      Rails.root.join("lib", "newman_runner.js").to_s,
      "--collection", collection_path.to_s,
      "--out-dir", run_dir.to_s,
      "--report-json", report_json_path.to_s,
      "--report-html", report_html_path.to_s
    ]
    cmd += [ "--environment", environment_path.to_s ] if environment_path.present?
    cmd += [ "--vars", vars_path.to_s ] if vars_path.present?

    stdout_buffer = +""
    stderr_buffer = +""

    File.open(log_path, "a") do |log|
      log.sync = true

      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait|
        stdin.close

        out_thread = Thread.new do
          stdout.each_line do |line|
            log.write("[stdout] #{line}")
            stdout_buffer = append_buffer(stdout_buffer, line)
          end
        end

        err_thread = Thread.new do
          stderr.each_line do |line|
            log.write("[stderr] #{line}")
            stderr_buffer = append_buffer(stderr_buffer, line)
          end
        end

        out_thread.join
        err_thread.join
        status = wait.value

        finished_at = Time.current
        duration_ms = ((finished_at - @run.started_at) * 1000).to_i

        @run.update!(
          status: status.success? ? "success" : "failed",
          finished_at: finished_at,
          duration_ms: duration_ms,
          exit_code: status.exitstatus,
          stdout: stdout_buffer,
          stderr: stderr_buffer
        )
      end
    end
  rescue => e
    @run.status = "failed" if @run&.persisted?
    @run.stderr = [ @run.stderr, e.class.name, e.message ].compact.join("\n") if @run
    @run.finished_at = Time.current if @run
    @run.save! if @run&.persisted?
    raise
  end

  private

  def normalize_vars(input)
    vars = []
    if input.is_a?(Array)
      input.each do |item|
        next unless item.is_a?(Hash)
        key = item["key"] || item[:key]
        value = item["value"] || item[:value]
        next if key.nil?
        vars << { "key" => key.to_s, "value" => value.to_s, "enabled" => true }
      end
    elsif input.is_a?(Hash)
      input.each do |key, value|
        vars << { "key" => key.to_s, "value" => value.to_s, "enabled" => true }
      end
    end

    vars
  end

  def append_buffer(buffer, line)
    buffer << line
    buffer = buffer[-LOG_BUFFER_LIMIT..] if buffer.length > LOG_BUFFER_LIMIT
    buffer
  end
end
