## Changelog

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

## W11 Optimiser 1.1

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

## CPU Benchmark

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

## 2026-07-12 Update 4

## Internet Quality Tester 1.0.0

- Added multi-round latency, jitter and packet-loss approximation testing.
- Added download speed, consistency and responsiveness-under-load measurements.
- Added Cloudflare edge DNS resolver timing.
- Added stability labels and suitability ratings for video calls, gaming, streaming and large downloads.
- Added Light, Standard and Thorough test modes with estimated data usage.
- Added cancellation, background-tab detection and clear browser limitation warnings.
- Added methodology, source-code and project information pages.
- Deployed free-plan Cloudflare Worker endpoints for ping, download and DNS testing.
- Added regression tests for calculations, ratings, endpoint limits and site integration.
- Added the Internet Quality Tester to the website’s project menu.

## 2026-07-12 Update 4.1

## Internet Quality Tester 1.1.0

- Improved download accuracy for high-speed internet connections.
- Added longer download measurements with increased test payloads.
- Added concurrent download streams to better saturate fast connections.
- Excluded the first 512 KiB of each stream from timing to reduce connection-startup bias.
- Replaced short byte-based samples with steadier 250 ms throughput windows.
- Separated latency rounds from bandwidth-heavy load rounds.
- Updated estimated data usage for every test depth.
- Increased the server-side download cap from 16 MiB to 32 MiB per request.
- Added Cloudflare-native rate limiting for all test requests.
- Added a separate stricter limit for bandwidth-heavy downloads.
- Added HTTP 429 handling and a clear one-minute retry message.
- Added regression coverage for download caps, profiles and rate-limit responses.
- Updated the browser cache version so the improved tester loads immediately after deployment.

## 2026-07-12 Update 4.2

## WiFi Tester 1.1.1

- Renamed Internet Quality Tester to WiFi Tester.
- Updated the project name across the homepage, tester, methodology page and source viewer.
- Removed the Connection Suitability section and its rating cards.
- Removed the unused video-call, gaming, streaming and large-download scoring logic.
- Fixed NaN% appearing in download and loaded-latency spread results.
- Updated spread calculations to ignore rounds without applicable measurements.
- Added regression checks to prevent the NaN% error from returning.
- Updated the browser cache version so visitors receive the corrected tester immediately.

## 2026-07-12 Update 4.3

## Site Design Consistency

- Added a shared typography stylesheet across all 12 website pages.
- Standardized the monospace font stack for headings, body text, buttons, inputs, selections and code.
- Aligned the Internet Tester typography with CPU Benchmark.
- Updated the Internet Tester source page to match the CPU and W11 source-page design.
- Preserved responsive sizing for longer page titles and smaller screens.
- Added regression coverage to ensure every HTML page uses the shared typography stylesheet.
- Added direct code-viewer links to filenames on all three project information pages.
- Renamed WiFi Tester to Internet Tester to reflect support for WiFi, Ethernet, 4G and 5G connections.
- Removed duplicate divider lines from CPU Benchmark and Internet Tester while retaining their progress indicators.

## 2026-07-13 Update 4.4 HotFix

## Internet Tester

- Fixed origin headers for the www. domain.
- Fixed the default download endpoint returning 64 KB instead of 1 MB.
- Fixed a console error when stopping an active download test.
- Preserved the existing request and download rate limits.
- Added regression coverage for origins, default downloads, and cancellation.
- Removed the explanatory PowerShell comment block from w11-optimiser.ps1.
- Removed setup comments from w11-optimiser-tests.ps1.
- Removed an inline comment from internet-quality.js.
- Rebuilt w11-optimiser.zip so the downloadable package contains the cleaned files.

## 2026-07-13 Update 4.5 Visuals and HotFix

## Internet Tester UI

- Updated the header layout to more closely match CPU Benchmark.
- Increased the Internet Tester heading size.
- Improved responsive scaling for desktop and mobile screens.
- Prevented the Stability rating from wrapping onto multiple lines.
- Capitalised all words in test status messages.
- Moved estimated data usage into the Browser Estimate box.
- Added usage details for Light, Standard and Thorough tests.

## W11 Optimiser 1.1.2

- Fixed an outdated SHA-256 value in the release manifest.
- Matched the manifest checksum with the current PowerShell script.
- Rebuilt and verified the downloadable ZIP.
- Added a regression test to detect future manifest checksum mismatches.
- Fixed the “Downloaded script hash did not match” error.