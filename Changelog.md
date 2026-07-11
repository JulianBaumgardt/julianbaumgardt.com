# Changelog

## 2026-07-08 Update 2.0

- Added W11 Optimiser guide page.
- Added PowerShell and download instructions.
- Added copy buttons for the PowerShell command.
- Added sanitized run report demo page.
- Updated W11 Optimiser menu wording and spacing.
- Improved script flow so users return to the menu after actions.
- Fixed report actions being shown as failed.
- Added Wi-Fi adapter power-management optimisation.
- Updated W11 Optimiser zip.
- Added favicon.
- Added robots.txt.
- Cleaned project dropdown links.

## 2026-07-08 Update 2.1

- Added updated W11 Optimiser menu screenshot to the guide page.
- Added a W11 Optimiser code selector page.
- Added a CPU Benchmark code selector page.
- Added `View Source Code` links for CPU Benchmark and W11 Optimiser.
- Added the W11 bootstrapper to the visible W11 code list.
- Reworked the home page project dropdowns to be simpler and less file-heavy.
- Removed nested source-file dropdowns from the home page.
- Changed final-link symbols from `+` to `->` so `+/-` only means expand or collapse.
- Changed the W11 download link symbol to `v`.
- Added `how to use guide` back to the W11 Optimiser dropdown.
- Moved `download zip` to the bottom of the W11 Optimiser dropdown.
- Made `about this project` sit near the bottom of project dropdowns.
- Made fonts consistent across the website, including the W11 run report demo page.
- Renamed W11 guide button text from `Show Code` to `View Source Code`.
- Standardized W11 navigation wording with `Back To W11 Guide`.
- Shortened and resized the W11 code page heading/summary.
- Verified main pages and project links on localhost.

## 2026-07-10 Update 3.0

### W11 Optimiser 1.1

- Changed Safe Optimise to create a dedicated temporary power plan for each run.
- Original Windows power plans are no longer edited by the optimiser.
- Updated Undo Latest Run to restore the previous plan and remove the run-specific W11 Optimiser plan.
- Added cleanup if power-plan configuration fails partway through.
- Made failed registry exports stop Safe Optimise before settings can be changed.
- Hardened undo so it removes only optimiser-created registry values, never an entire registry path.
- Added version `1.1.0` to the PowerShell script, CMD launcher, and generated reports.
- Added `w11-optimiser.manifest.json` with a release version and SHA-256 checksum.
- Updated the web PowerShell bootstrapper to verify the downloaded script hash before opening the menu.
- Added `w11-optimiser-tests.ps1` with Pester regression checks for the power-plan and registry-undo safeguards.
- Rebuilt `w11-optimiser.zip` and verified it matches the source folder.
- Updated the W11 README, About page, guide page, code selector, and run-report demo to explain the new behaviour.
- Added JSON syntax highlighting and copy fallback support to the code viewer.
- Added `.gitignore` rules for macOS metadata and temporary files.

### CPU Benchmark

- Added worker startup, synchronized-start, and long-round timeouts so failed worker runs show a useful error instead of hanging.
- Added Cloudflare deployment headers for cross-origin isolation, enabling the more precise SharedArrayBuffer and Atomics start barrier.
- Expanded the CPU Benchmark About page with browser limitations, uncontrollable external factors, and an explanation of logical threads versus physical CPU cores.
- Added a hybrid CPU example explaining why 14 physical cores can correctly appear as 20 browser threads.
- Verified the CPU Benchmark regression tests pass.

### Verification

- Verified the W11 script SHA-256 matches the published release manifest.
- Verified the downloadable ZIP matches the W11 source folder.

## 2026-07-11 Update 3.1 HotFix

## W11 Optimiser 1.1.1

- Fixed a PowerShell parser error that prevented the optimiser from starting.
- Updated the release manifest and SHA-256 checksum.
- Rebuilt the downloadable ZIP.
- Added a regression check to prevent the error from returning.