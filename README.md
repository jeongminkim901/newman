# Postman Rails Runner

A Rails UI to upload a Postman collection, provide IP/token overrides, and run Newman immediately. Reports are saved as HTML and JSON with run history.

## Requirements
- Ruby (3.3+)
- Node.js (18+)

## Setup
```powershell
cd C:\dev\postman-rails-runner
$env:Path = 'C:\Ruby33-x64\bin;' + $env:Path
bundle install
npm install
bundle exec rails db:migrate
bundle exec rails db:setup:queue
```

## Run
```powershell
bundle exec rails s
```
Open http://localhost:3000

## Background Runs (Queue)
- Check **Run in background (queue)** on the new run form.
- Start a worker:
```powershell
bundle exec rails solid_queue:start
```

## Notes
- Reports are stored under `storage/runs/<id>/`.
- Live logs stream while a run is queued or running.
