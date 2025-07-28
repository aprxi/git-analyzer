# git-analyzer

A lean, dependency-free command-line tool written in Zig that analyzes Git repository history and provides weekly productivity metrics.

## Features

- **Daily View (Default)**: Last 30 days with daily breakdown - perfect for recent productivity tracking
- **Monthly History**: Use `--history` for long-term trends and monthly aggregation
- **Insightful Metrics**:
  - Total commits per day/month
  - Lines added and deleted (color-coded)
  - Average commit size
  - Refactoring ratio (lines deleted / lines added)
- **Summary Totals**: Overall statistics across the entire period
- **Color Output**: Green for additions, red for deletions (disable with `--no-color`)
- **Large Repository Support**: Streaming processing handles millions of commits
- **Zero Dependencies**: Uses only Zig standard library and shells out to `git`
- **Container-based Build**: Supports both Docker and Podman

## Requirements

- Git (must be in PATH)
- Docker or Podman (for building)

## Building

```bash
# Build the tool (creates zig-out/bin/git-insight)
make build

# Or build and run in one command
make run
```

## Usage

```bash
# Analyze last 30 days (default daily view)
./zig-out/bin/git-insight

# Monthly history for last year
./zig-out/bin/git-insight --history

# Last 60 days, daily view
./zig-out/bin/git-insight --since="60 days ago"

# Last 2 years, monthly view
./zig-out/bin/git-insight --history --since="2 years ago"

# Disable colors for scripts
./zig-out/bin/git-insight --no-color

# Using make
make run args='--history'
make run args='--since="90 days ago"'
```

## Example Output

**Daily View (Default):**
```
Git Insight Daily Report for the last 30 days ago

| Date         | Commits | Lines Added | Lines Deleted | Avg. Commit Size | Refactoring Ratio |
|--------------|---------|-------------|---------------|------------------|-------------------|
| Jul 25, 2025 |       3 | +245        | -12           |               86 |              0.05 |
| Jul 26, 2025 |       8 | +1200       | -350          |              194 |              0.29 |
| Jul 27, 2025 |       5 | +456        | -23           |               96 |              0.05 |
|--------------|---------|-------------|---------------|------------------|-------------------|
| TOTAL        |      16 | +1901       | -385          |              143 |              0.20 |
```

**Monthly History (`--history`):**
```
Git Insight Monthly History for the last 1 year ago

| Month        | Commits | Lines Added | Lines Deleted | Avg. Commit Size | Refactoring Ratio |
|--------------|---------|-------------|---------------|------------------|-------------------|
| Jan 2025     |      45 | +2150       | -800          |               66 |              0.37 |
| Feb 2025     |      52 | +3200       | -1200         |               85 |              0.38 |
| Mar 2025     |      38 | +1800       | -450          |               59 |              0.25 |
|--------------|---------|-------------|---------------|------------------|-------------------|
| TOTAL        |     135 | +7150       | -2450         |               71 |              0.34 |
```

*Note: In terminals with color support, additions appear in green and deletions in red.*

## Development

```bash
# Launch interactive shell in build container
make shell

# Clean build artifacts
make clean

# Clean everything including Docker image
make clean-all
```

## Architecture

The tool executes `git log` with specific formatting options and parses the output to calculate metrics. It groups commits by week and computes:

1. **Refactoring Ratio**: Higher values suggest more code cleanup/refactoring
2. **Average Commit Size**: Helps identify commit granularity patterns
3. **Weekly Trends**: Visual representation of development activity

## Implementation Details

- Written in Zig 0.13.0
- Uses `git log --numstat` for accurate line counts
- Handles binary files gracefully (excludes from line counts)
- Week starts on Sunday (configurable in code)
- Single static executable output
## Changelog

- **v2.0**: 
  - 🔥 **New default**: Daily view for last 30 days (much more actionable!)
  - 📊 **History mode**: `--history` flag for monthly aggregation
  - 🚀 **Large repo support**: Fixed `StdoutStreamTooLong` error with streaming
  - 🎯 **Better UX**: Daily for recent work, monthly for trends
- **v1.1**: Added color output, week date ranges, and summary totals
- **v1.0**: Initial release with basic weekly statistics
