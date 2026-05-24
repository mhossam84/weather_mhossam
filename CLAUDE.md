# CLAUDE.md

This file documents the codebase for AI assistants working in this repository.

## Project Overview

A minimal Bash shell scripting project that fetches historical daily weather data (maximum temperature) for Gainesville Regional Airport (GNV, Florida) from the Weather Underground API and writes it to a local file.

## Repository Structure

```
weather_mhossam/
├── weather.sh        # Hardcoded fetcher for a single historical date
├── weather_new.sh    # Dynamic fetcher using yesterday's date
└── README.md         # Minimal project title only
```

## Scripts

### `weather.sh`
Fetches weather data for a single hardcoded date (2016-09-06). Downloads CSV to `gnv.txt`, extracts the max temperature from column 2 using `awk`, and prints it.

```bash
curl "https://www.wunderground.com/history/airport/GNV/2016/09/06/DailyHistory.heml?&format=1" > gnv.txt
maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`
echo The Max temp is $maxTemp
```

Note: the URL has a typo — `.heml` instead of `.html`.

### `weather_new.sh`
Improved version that dynamically computes yesterday's date using `date -d yesterday`, then fetches and parses the same Weather Underground endpoint for that date.

```bash
year=`date -d yesterday +%Y`
month=`date -d yesterday +%m`
day=`date -d yesterday +%d`
curl "https://www.wunderground.com/history/airport/GNV/$year/$month/$day/DailyHistory.html?&format=1" > gnv.txt
maxTemp=`awk -F',' '{print $2}' gnv.txt | sort -n | tail -n1`
echo The Max temp is $maxTemp
```

## API

- **Provider**: Weather Underground (legacy/historical endpoint)
- **Format**: CSV, `?&format=1`
- **URL pattern**: `https://www.wunderground.com/history/airport/GNV/{YYYY}/{MM}/{DD}/DailyHistory.html?&format=1`
- **Station**: `GNV` — Gainesville Regional Airport, Florida
- **Note**: The Weather Underground free history API was discontinued after 2018. These scripts are likely non-functional without a valid API key or an alternative data source.

## Key Conventions

- Shell: `#!/bin/bash`
- Date computation: GNU `date -d yesterday` (Linux-specific; not compatible with macOS `date`)
- Output file: always `gnv.txt` in the current working directory
- Temperature extracted from CSV column 2 (`awk -F','`), sorted numerically, last value taken as max
- No error handling, no API key, no flags or arguments

## Running the Scripts

```bash
chmod +x weather.sh weather_new.sh
./weather_new.sh   # preferred — uses dynamic date
./weather.sh       # hardcoded to 2016-09-06
```

Output is written to `gnv.txt` in the current directory. The max temperature is also printed to stdout.

## Development Notes

- No package manager, build system, test framework, or CI/CD pipeline exists.
- No environment variables or `.env` files are used.
- The only external dependency is `curl`, `awk`, `sort`, and GNU `date` — all standard on Linux.
- `weather_new.sh` supersedes `weather.sh`; prefer it for any new work.
- If extending this project, consider: adding error handling (`set -euo pipefail`), supporting arbitrary dates via CLI arguments, and replacing the deprecated API with an active weather data source.

## Git Branches

- `master` — main branch
- `claude/claude-md-docs-IGTwl` — documentation branch (this file was created here)
