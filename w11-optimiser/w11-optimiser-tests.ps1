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
        $source | Should -Match 'OptimisedPowerSchemeName -like "W11 Optimiser \*"'
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

    It "does not change network power settings without a restorable backup" {
        $source | Should -Match '\$script:NetworkStateBackupReady = \$true'
        $source | Should -Match 'if \(-not \$script:NetworkStateBackupReady\)'
    }

    It "reports optional step failures instead of claiming every change succeeded" {
        $source | Should -Match 'function Get-StepReportLine'
        $source | Should -Match '\$script:StepResults\[\$Name\] = "Failed:'
        $source | Should -Not -Match '\[OK\] POWER PLAN: CREATED A DEDICATED W11 OPTIMISER POWER PLAN FOR THIS RUN\.'
    }

    It "validates the supported OS and saved state before state-changing operations" {
        $source | Should -Match 'function Assert-Windows11Client'
        $source | Should -Match 'RunKind = "W11Optimiser"'
        $source | Should -Match 'StateSchemaVersion = \$StateSchemaVersion'
        $source | Should -Match 'Refused unexpected network registry path'
    }

    It "matches the SHA-256 published in the release manifest" {
        $actualHash = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $actualHash | Should -Be $manifest.sha256.ToLowerInvariant()
    }
}
