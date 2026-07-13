$scriptPath = Join-Path $PSScriptRoot "w11-optimiser.ps1"
$manifestPath = Join-Path $PSScriptRoot "w11-optimiser.manifest.json"
$source = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
$manifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json

Describe "W11 Optimiser safety regressions" {
    It "uses a dedicated power plan rather than modifying an existing plan" {
        $source | Should -Match "function New-OptimisedPowerScheme"
        $source | Should -Match '/DUPLICATESCHEME'
        $source | Should -Match "OptimisedPowerSchemeGuid"
    }

    It "removes the dedicated power plan during undo" {
        $source | Should -Match "function Remove-OptimisedPowerScheme"
        $source | Should -Match 'Remove-OptimisedPowerScheme -PowerSchemeGuid \$state\.OptimisedPowerSchemeGuid'
    }

    It "stops before optimisation when an existing registry key cannot be exported" {
        $source | Should -Match 'Could not back up \$RegPath before optimisation\. No settings were changed\.'
        $source | Should -Not -Match "ExportFailedBeforeOptimisation"
    }

    It "only removes optimiser-created values for keys that were absent before the run" {
        $source | Should -Match '\$marker\.Status -ne "MissingBeforeOptimisation"'
        $source | Should -Match "function Remove-RegistryValuesIfMissingBeforeRun"
        $source | Should -Not -Match 'Remove-Item -Path \$RegistryPath -Recurse'
    }

    It "delimits interpolated variables that are immediately followed by a colon" {
        $unsafeVariableBeforeColon = '\$(?!(?:env|script|global|local|private):)[A-Za-z_][A-Za-z0-9_]*:'
        $source | Should -Not -Match $unsafeVariableBeforeColon
    }

    It "matches the SHA-256 published in the release manifest" {
        $actualHash = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $actualHash | Should -Be $manifest.sha256.ToLowerInvariant()
    }
}
