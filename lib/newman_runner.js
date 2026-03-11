const fs = require("fs");
const path = require("path");
const newman = require("newman");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) continue;
    const value = argv[i + 1];
    args[key.slice(2)] = value;
    i += 1;
  }
  return args;
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

const args = parseArgs(process.argv.slice(2));
if (!args.collection) {
  console.error("Missing --collection");
  process.exit(2);
}
if (!args.reportJson || !args.reportHtml) {
  console.error("Missing --report-json or --report-html");
  process.exit(2);
}

const collection = readJson(args.collection);
const environment = args.environment ? readJson(args.environment) : undefined;
const envVar = args.vars ? readJson(args.vars) : undefined;

const reporters = ["cli", "json", "htmlextra"];
const reporter = {
  json: { export: args.reportJson },
  htmlextra: {
    export: args.reportHtml,
    logs: true,
    title: "Newman Report",
    browserTitle: "Newman Report",
    omitHeaders: false
  }
};

newman.run(
  { collection, environment, envVar, reporters, reporter },
  (err, summary) => {
    if (err) {
      console.error(err);
      process.exit(1);
    }
    if (summary.error) {
      console.error(summary.error);
      process.exit(1);
    }
    process.exit(summary.run.failures && summary.run.failures.length ? 1 : 0);
  }
);
