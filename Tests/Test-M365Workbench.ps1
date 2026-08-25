[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $appRoot 'M365Workbench.Core.psm1'
$clipboardPath = Join-Path $appRoot 'SecureClipboard.cs'
$mainScriptPath = Join-Path $appRoot 'M365Workbench.ps1'
$iconPath = Join-Path $appRoot 'assets\M365Workbench.ico'
$shortcutInstallerPath = Join-Path $appRoot 'Install-DesktopShortcut.ps1'
$iconBuildScriptPath = Join-Path $appRoot 'assets\Build-Icon.ps1'
$launcherBuildScriptPath = Join-Path $appRoot 'assets\Build-Launcher.ps1'
$shellIdentityPath = Join-Path $appRoot 'assets\WindowsShellIdentity.cs'
$licensePath = Join-Path $appRoot 'LICENSE'
$readmePath = Join-Path $appRoot 'README.md'
$securityPolicyPath = Join-Path $appRoot 'SECURITY.md'
$launcherTestPath = Join-Path $appRoot 'artifacts\M365Workbench.Launcher.Test.exe'
$shortcutIdentityTestPath = Join-Path $appRoot "artifacts\M365Workbench.Identity.$PID.Test.lnk"
$visualPreviewTestPath = Join-Path $appRoot "artifacts\M365Workbench.Visual.$PID.Test.png"
$expectedAppUserModelId = 'M365Workbench.Desktop'

Import-Module $modulePath -Force
if ($null -eq ('M365Workbench.Security.SecureClipboard' -as [type])) {
    Add-Type -Path $clipboardPath
}
if ($null -eq ('M365Workbench.WindowsShellIdentity' -as [type])) {
    Add-Type -Path $shellIdentityPath
}

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Condition) {
        $script:Failed++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        return
    }

    $script:Passed++
    Write-Host "PASS  $Name" -ForegroundColor Green
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory)][string]$Name
    )

    Assert-True -Condition ($Actual -eq $Expected) -Name "$Name (expected '$Expected', got '$Actual')"
}

$plainPassword = 'R4ndom!LAPS#2026'
$encodedPassword = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($plainPassword))
Assert-Equal -Actual (ConvertFrom-LapsPasswordBase64 -PasswordBase64 $encodedPassword) -Expected $plainPassword -Name 'UTF-16LE LAPS password decoding'

$utf8OddPassword = 'LAPS-words-are-UTF8-now-2026!xyzz'
$utf8OddPayload = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($utf8OddPassword))
Assert-Equal -Actual (ConvertFrom-LapsPasswordBase64 -PasswordBase64 $utf8OddPayload) -Expected $utf8OddPassword -Name 'Odd-byte-length UTF-8 LAPS password decoding'

$utf8EvenPassword = 'Abcd!234'
$utf8EvenPayload = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($utf8EvenPassword))
Assert-Equal -Actual (ConvertFrom-LapsPasswordBase64 -PasswordBase64 $utf8EvenPayload) -Expected $utf8EvenPassword -Name 'Even-byte-length UTF-8 is not mistaken for UTF-16LE'

$utf8BomBytes = [byte[]](0xEF, 0xBB, 0xBF) + [Text.UTF8Encoding]::new($false).GetBytes('Bom!Pass9')
$utf8BomPayload = [Convert]::ToBase64String($utf8BomBytes)
Assert-Equal -Actual (ConvertFrom-LapsPasswordBase64 -PasswordBase64 $utf8BomPayload) -Expected 'Bom!Pass9' -Name 'UTF-8 BOM is handled without entering the password'
[Array]::Clear($utf8BomBytes, 0, $utf8BomBytes.Length)

$invalidPayloadRejected = $false
try {
    $null = ConvertFrom-LapsPasswordBase64 -PasswordBase64 ([Convert]::ToBase64String([byte[]](1, 2, 3)))
}
catch {
    $invalidPayloadRejected = $true
}
Assert-True -Condition $invalidPayloadRejected -Name 'Control-character password payload is rejected'

$credentials = @(
    [pscustomobject]@{ accountName = 'Administrator'; backupDateTime = '2026-08-01T10:00:00Z'; passwordBase64 = 'old' },
    [pscustomobject]@{ accountName = 'LapsAdmin'; backupDateTime = '2026-08-24T10:00:00Z'; passwordBase64 = 'new' }
)
Assert-Equal -Actual (Select-CurrentLapsCredential -Credentials $credentials).accountName -Expected 'LapsAdmin' -Name 'Newest credential is selected independently of array order'

$message = 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code A1B2C3D4E to authenticate.'
$deviceCode = Get-DeviceCodeFromMessage -Message $message
Assert-Equal -Actual $deviceCode.UserCode -Expected 'A1B2C3D4E' -Name 'Microsoft Graph device-code prompt is parsed'
Assert-True -Condition ($null -eq (Get-DeviceCodeFromMessage -Message 'ordinary output')) -Name 'Unrelated output is ignored by device-code parser'

$requiredScopes = @('Device.Read.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceLocalCredential.Read.All')
$tenantId = [Guid]'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
$validContext = [pscustomobject]@{ AuthType = 'Delegated'; Account = 'laps-admin@contoso.onmicrosoft.com'; TenantId = $tenantId; Scopes = $requiredScopes }
$validation = Test-LapsGraphContext -Context $validContext -ExpectedAccount 'laps-admin@contoso.onmicrosoft.com' -ExpectedTenantId $tenantId -RequiredScopes $requiredScopes
Assert-True -Condition $validation.IsValid -Name 'Expected delegated Graph context is accepted'

$wrongAccountContext = [pscustomobject]@{ AuthType = 'Delegated'; Account = 'daily.user@contoso.com'; TenantId = $tenantId; Scopes = $requiredScopes }
$validation = Test-LapsGraphContext -Context $wrongAccountContext -ExpectedAccount 'laps-admin@contoso.onmicrosoft.com' -ExpectedTenantId $tenantId -RequiredScopes $requiredScopes
Assert-Equal -Actual $validation.Reason -Expected 'WrongAccount' -Name 'Daily user account is rejected'

$wrongTenantContext = [pscustomobject]@{ AuthType = 'Delegated'; Account = 'laps-admin@contoso.onmicrosoft.com'; TenantId = [Guid]'00000000-0000-0000-0000-000000000001'; Scopes = $requiredScopes }
$validation = Test-LapsGraphContext -Context $wrongTenantContext -ExpectedAccount 'laps-admin@contoso.onmicrosoft.com' -ExpectedTenantId $tenantId -RequiredScopes $requiredScopes
Assert-Equal -Actual $validation.Reason -Expected 'WrongTenant' -Name 'Unexpected Microsoft Entra tenant is rejected'

$appOnlyContext = [pscustomobject]@{ AuthType = 'AppOnly'; Account = $null; TenantId = $tenantId; Scopes = $requiredScopes }
$validation = Test-LapsGraphContext -Context $appOnlyContext -ExpectedAccount 'laps-admin@contoso.onmicrosoft.com' -ExpectedTenantId $tenantId -RequiredScopes $requiredScopes
Assert-Equal -Actual $validation.Reason -Expected 'NotDelegated' -Name 'App-only Graph context is rejected for password retrieval'

$now = [DateTimeOffset]::Now
$managed = @(
    [pscustomobject]@{ id='old'; deviceName='DEMO-DEVICE-PRIMARY'; azureADDeviceId='11111111-1111-1111-1111-111111111111'; userDisplayName='Old Assignment'; userPrincipalName='old@contoso.com'; serialNumber='DEMO-SERIAL-OLD'; operatingSystem='Windows'; model='Old Model'; lastSyncDateTime=$now.AddDays(-10); complianceState='unknown' },
    [pscustomobject]@{ id='new'; deviceName='DEMO-DEVICE-PRIMARY'; azureADDeviceId='11111111-1111-1111-1111-111111111111'; userDisplayName='Current User'; userPrincipalName='current@contoso.com'; serialNumber='DEMO-SERIAL-NEW'; operatingSystem='Windows'; model='New Model'; lastSyncDateTime=$now.AddHours(-1); complianceState='compliant' },
    [pscustomobject]@{ id='different'; deviceName='DEMO-DEVICE-COLLISION'; azureADDeviceId='22222222-2222-2222-2222-222222222222'; userDisplayName='No Laps'; userPrincipalName='nolaps@contoso.com'; serialNumber='DEMO-SERIAL-NO-LAPS'; operatingSystem='Windows'; model='Model B'; lastSyncDateTime=$now; complianceState='compliant' },
    [pscustomobject]@{ id='mac'; deviceName='DEMO-DEVICE-NONWINDOWS'; azureADDeviceId='33333333-3333-3333-3333-333333333333'; userDisplayName='Mac User'; userPrincipalName='mac@contoso.com'; serialNumber='DEMO-SERIAL-MAC'; operatingSystem='macOS'; model='MacBook'; lastSyncDateTime=$now; complianceState='compliant' }
)
$laps = @(
    [pscustomobject]@{ id='11111111-1111-1111-1111-111111111111'; deviceName='DEMO-DEVICE-PRIMARY'; lastBackupDateTime=$now.AddDays(-2); refreshDateTime=$now.AddDays(28) },
    [pscustomobject]@{ id='44444444-4444-4444-4444-444444444444'; deviceName='DEMO-DEVICE-COLLISION'; lastBackupDateTime=$now.AddDays(-1); refreshDateTime=$now.AddDays(29) }
)
$rows = @(Merge-IntuneLapsDeviceData -ManagedDevices $managed -LapsMetadata $laps)
Assert-Equal -Actual $rows.Count -Expected 3 -Name 'Windows inventory is deduplicated and Entra-only LAPS device is included'
Assert-Equal -Actual @($rows | Where-Object DeviceName -eq 'DEMO-DEVICE-PRIMARY').Count -Expected 1 -Name 'Duplicate Intune records collapse to one row'
Assert-Equal -Actual ($rows | Where-Object DeviceName -eq 'DEMO-DEVICE-PRIMARY').PrimaryUser -Expected 'Current User' -Name 'Newest Intune record wins deduplication'
Assert-Equal -Actual ($rows | Where-Object EntraDeviceId -eq '22222222-2222-2222-2222-222222222222').LapsAvailable -Expected $false -Name 'LAPS metadata is never joined by device name alone'
Assert-Equal -Actual ($rows | Where-Object EntraDeviceId -eq '44444444-4444-4444-4444-444444444444').InventorySource -Expected 'Microsoft Entra' -Name 'Recoverable Entra-only device is clearly labeled'
$entraOnlyInventoryRow = $rows | Where-Object EntraDeviceId -eq '44444444-4444-4444-4444-444444444444'
Assert-True -Condition $entraOnlyInventoryRow.IsEntraOnly -Name 'Entra-only inventory mismatch is exposed as a management state'
Assert-Equal -Actual $entraOnlyInventoryRow.ManagementStateDisplay -Expected 'Entra only' -Name 'Entra-only management state has a concise display label'
Assert-Equal -Actual $entraOnlyInventoryRow.LastSyncDisplay -Expected 'Not in Intune' -Name 'Entra-only device does not misleadingly report an Intune sync of Never'
Assert-True -Condition $entraOnlyInventoryRow.SearchText.Contains('entra only') -Name 'Search index includes the Entra-only management state'
Assert-True -Condition ($rows | Where-Object DeviceName -eq 'DEMO-DEVICE-PRIMARY').IsIntuneManaged -Name 'Matched Intune inventory is explicitly marked as managed'
Assert-True -Condition (($rows | Where-Object DeviceName -eq 'DEMO-DEVICE-PRIMARY').SearchText.Contains('current@contoso.com')) -Name 'Search index includes the primary user UPN'

$portalDevice = [pscustomobject]@{
    IntuneDeviceId = 'aaaaaaaa-1111-4111-8111-111111111111'
    EntraObjectId = 'bbbbbbbb-2222-4222-8222-222222222222'
}
$intunePortalUri = Get-DeviceAdminPortalUri -Portal Intune -Device $portalDevice
$entraPortalUri = Get-DeviceAdminPortalUri -Portal Entra -Device $portalDevice
Assert-Equal -Actual $intunePortalUri.Host -Expected 'intune.microsoft.com' -Name 'Intune deep link is restricted to the Intune admin center'
Assert-True -Condition ($intunePortalUri.Fragment.EndsWith('/mdmDeviceId/aaaaaaaa-1111-4111-8111-111111111111')) -Name 'Intune deep link targets the selected managed-device record'
Assert-Equal -Actual $entraPortalUri.Host -Expected 'entra.microsoft.com' -Name 'Entra deep link is restricted to the Entra admin center'
Assert-True -Condition ($entraPortalUri.Fragment.EndsWith('/objectId/bbbbbbbb-2222-4222-8222-222222222222')) -Name 'Entra deep link targets the selected directory object'
$invalidPortalDevice = [pscustomobject]@{ IntuneDeviceId = 'not-a-guid/../../elsewhere'; EntraObjectId = [Guid]::Empty.ToString() }
Assert-True -Condition ($null -eq (Get-DeviceAdminPortalUri -Portal Intune -Device $invalidPortalDevice)) -Name 'Malformed portal identifiers cannot create an external link'
Assert-True -Condition ($null -eq (Get-DeviceAdminPortalUri -Portal Entra -Device $invalidPortalDevice)) -Name 'Empty portal identifiers cannot create an external link'

Assert-True -Condition (Test-BitLockerRecoveryKey '111111-222222-333333-444444-555555-666666-777777-888888') -Name 'A canonical 48-digit BitLocker recovery key is accepted'
Assert-True -Condition (-not (Test-BitLockerRecoveryKey '111111-222222-333333-444444-555555-666666-777777-88888X')) -Name 'A malformed BitLocker recovery key is rejected'

$bitLockerMetadata = @(
    [pscustomobject]@{ id='aaaaaaaa-1111-4111-8111-111111111111'; deviceId='11111111-1111-1111-1111-111111111111'; createdDateTime=$now.AddDays(-8); volumeType='operatingSystemVolume' },
    [pscustomobject]@{ id='bbbbbbbb-1111-4111-8111-111111111111'; deviceId='11111111-1111-1111-1111-111111111111'; createdDateTime=$now.AddDays(-2); volumeType='fixedDataVolume' },
    [pscustomobject]@{ id='cccccccc-4444-4444-8444-444444444444'; deviceId='44444444-4444-4444-4444-444444444444'; createdDateTime=$now.AddDays(-3); volumeType='operatingSystemVolume' }
)
$entraDevices = @(
    [pscustomobject]@{ id='dddddddd-1111-4111-8111-111111111111'; deviceId='11111111-1111-1111-1111-111111111111'; displayName='DEMO-DEVICE-PRIMARY'; operatingSystem='Windows'; operatingSystemVersion='10.0.26100'; trustType='AzureAd'; approximateLastSignInDateTime=$now.AddMinutes(-20) },
    [pscustomobject]@{ id='eeeeeeee-4444-4444-8444-444444444444'; deviceId='44444444-4444-4444-4444-444444444444'; displayName='DEMO-DEVICE-COLLISION'; operatingSystem='Windows'; operatingSystemVersion='10.0.26100'; trustType='ServerAd'; approximateLastSignInDateTime=$now.AddHours(-4) }
)
$recoveryRows = @(Merge-IntuneLapsDeviceData -ManagedDevices $managed -LapsMetadata $laps -BitLockerMetadata $bitLockerMetadata -EntraDevices $entraDevices)
$primaryDeviceRow = $recoveryRows | Where-Object EntraDeviceId -eq '11111111-1111-1111-1111-111111111111'
$differentRow = $recoveryRows | Where-Object EntraDeviceId -eq '22222222-2222-2222-2222-222222222222'
$entraOnlyRow = $recoveryRows | Where-Object EntraDeviceId -eq '44444444-4444-4444-4444-444444444444'
Assert-Equal -Actual $primaryDeviceRow.BitLockerKeyCount -Expected 2 -Name 'Multiple BitLocker metadata records are retained for one device'
Assert-Equal -Actual $primaryDeviceRow.BitLockerKeys[0].VolumeDisplay -Expected 'Fixed data volume' -Name 'BitLocker key choices are ordered newest first and labeled by volume'
Assert-Equal -Actual $differentRow.BitLockerAvailable -Expected $false -Name 'BitLocker metadata is never joined by device name alone'
Assert-Equal -Actual $entraOnlyRow.BitLockerAvailable -Expected $true -Name 'Entra-only recovery devices retain BitLocker metadata'
Assert-Equal -Actual $entraOnlyRow.TrustTypeDisplay -Expected 'Hybrid Microsoft Entra joined' -Name 'Entra join type is shown in friendly form'
Assert-True -Condition $primaryDeviceRow.RecoveryAvailable -Name 'Combined recovery readiness includes BitLocker or LAPS'
Assert-True -Condition ($null -eq (Get-DeviceAdminPortalUri -Portal Intune -Device $entraOnlyRow)) -Name 'Entra-only devices do not receive a misleading Intune link'
Assert-Equal -Actual (Get-DeviceAdminPortalUri -Portal Entra -Device $entraOnlyRow).Host -Expected 'entra.microsoft.com' -Name 'Entra-only devices retain their Entra link'

$friendly403 = Get-FriendlyLapsErrorMessage -ErrorCode 'Authorization_RequestDenied' -Message 'Access denied' -StatusCode 403
Assert-True -Condition ($friendly403 -match 'Cloud Device Administrator') -Name 'Permission errors provide an actionable least-privilege role'

$friendlyDecode = Get-FriendlyLapsErrorMessage -ErrorCode 'RuntimeException' -Message 'The LAPS password payload could not be decoded safely.'
Assert-True -Condition ($friendlyDecode -match 'updated utility') -Name 'Password decoding errors are distinguished from Graph failures'

Assert-True -Condition ([M365Workbench.Security.SecureClipboard]::ProtectionFormatsAvailable()) -Name 'Windows secure clipboard history/cloud exclusion formats are available'
Assert-True -Condition (Test-Path -LiteralPath $iconPath -PathType Leaf) -Name 'M365 Workbench icon asset exists'
$iconFrameCount = 0
if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    $iconBytes = [IO.File]::ReadAllBytes($iconPath)
    if ($iconBytes.Length -ge 6 -and [BitConverter]::ToUInt16($iconBytes, 0) -eq 0 -and [BitConverter]::ToUInt16($iconBytes, 2) -eq 1) {
        $iconFrameCount = [BitConverter]::ToUInt16($iconBytes, 4)
    }
}
Assert-Equal -Actual $iconFrameCount -Expected 9 -Name 'Windows icon contains the complete multi-size frame set'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Equal -Actual $parseErrors.Count -Expected 0 -Name 'Main WPF application parses without PowerShell syntax errors'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($shortcutInstallerPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Equal -Actual $parseErrors.Count -Expected 0 -Name 'Desktop shortcut installer parses without PowerShell syntax errors'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($iconBuildScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Equal -Actual $parseErrors.Count -Expected 0 -Name 'Icon build script parses without PowerShell syntax errors'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($launcherBuildScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Equal -Actual $parseErrors.Count -Expected 0 -Name 'GUI launcher build script parses without PowerShell syntax errors'

& $launcherBuildScriptPath -OutputPath $launcherTestPath | Out-Null
$launcherBytes = [IO.File]::ReadAllBytes($launcherTestPath)
$launcherPeOffset = [BitConverter]::ToInt32($launcherBytes, 0x3C)
$launcherSubsystem = [BitConverter]::ToUInt16($launcherBytes, $launcherPeOffset + 24 + 68)
Assert-Equal -Actual $launcherSubsystem -Expected 2 -Name 'Generated launcher uses the Windows GUI subsystem without a console window'

if (Test-Path -LiteralPath $shortcutIdentityTestPath -PathType Leaf) {
    Remove-Item -LiteralPath $shortcutIdentityTestPath -Force
}
$identityWriterScript = @'
$ErrorActionPreference = 'Stop'
Add-Type -Path $env:M365WB_IDENTITY_HELPER
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($env:M365WB_IDENTITY_SHORTCUT)
$shortcut.TargetPath = $env:M365WB_IDENTITY_TARGET
$shortcut.WorkingDirectory = $env:M365WB_IDENTITY_ROOT
$shortcut.Description = 'M365 Workbench identity test'
$shortcut.IconLocation = "$($env:M365WB_IDENTITY_TARGET),0"
$shortcut.Save()
$null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
$null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
$shortcut = $null
$shell = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[M365Workbench.WindowsShellIdentity]::SetShortcutAppId($env:M365WB_IDENTITY_SHORTCUT, $env:M365WB_IDENTITY_APPID)
'@
$identityWriterEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($identityWriterScript))
$identityEnvironment = @{
    M365WB_IDENTITY_HELPER  = $shellIdentityPath
    M365WB_IDENTITY_SHORTCUT = $shortcutIdentityTestPath
    M365WB_IDENTITY_TARGET  = $launcherTestPath
    M365WB_IDENTITY_ROOT    = $appRoot
    M365WB_IDENTITY_APPID   = $expectedAppUserModelId
}
try {
    foreach ($entry in $identityEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    $powerShellExecutable = (Get-Process -Id $PID).Path
    & $powerShellExecutable -NoLogo -NoProfile -NonInteractive -EncodedCommand $identityWriterEncoded | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The isolated shortcut identity writer exited with code $LASTEXITCODE."
    }
}
finally {
    foreach ($name in $identityEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
}
$actualShortcutAppId = [M365Workbench.WindowsShellIdentity]::GetShortcutAppId($shortcutIdentityTestPath)
Assert-Equal -Actual $actualShortcutAppId -Expected $expectedAppUserModelId -Name 'Windows shortcut stores the dedicated M365 Workbench AppUserModelID'

$mainSource = [IO.File]::ReadAllText($mainScriptPath)
$fixtureDeviceNames = @([regex]::Matches($mainSource, "(?:deviceName|displayName)='(?<name>[^']+)'" ) | ForEach-Object { $_.Groups['name'].Value })
$fixtureSerialNumbers = @([regex]::Matches($mainSource, "serialNumber='(?<serial>[^']+)'" ) | ForEach-Object { $_.Groups['serial'].Value })
Assert-True -Condition ($fixtureDeviceNames.Count -gt 0 -and @($fixtureDeviceNames | Where-Object { -not $_.StartsWith('DEMO-DEVICE-') }).Count -eq 0) -Name 'Every embedded device fixture is unmistakably synthetic'
Assert-True -Condition ($fixtureSerialNumbers.Count -gt 0 -and @($fixtureSerialNumbers | Where-Object { -not $_.StartsWith('DEMO-SERIAL-') }).Count -eq 0) -Name 'Every embedded serial-number fixture is unmistakably synthetic'
Assert-True -Condition ((Test-Path -LiteralPath $licensePath -PathType Leaf) -and [IO.File]::ReadAllText($licensePath).StartsWith('MIT License')) -Name 'Repository includes the MIT License'
Assert-True -Condition ((Test-Path -LiteralPath $readmePath -PathType Leaf) -and (Test-Path -LiteralPath $securityPolicyPath -PathType Leaf)) -Name 'Public README and security policy are present'
Assert-True -Condition ($mainSource.Contains('M365 Workbench') -and -not $mainSource.Contains('Entra + Intune Console')) -Name 'Application identity uses M365 Workbench throughout the UI'
Assert-True -Condition ($mainSource.Contains("`$appUserModelId = '$expectedAppUserModelId'") -and $mainSource.Contains('[M365Workbench.WindowsShellIdentity]::SetCurrentProcessAppId($appUserModelId)') -and $mainSource.Contains('[M365Workbench.WindowsShellIdentity]::SetWindowAppId($windowHandle, $appUserModelId)')) -Name 'Running WPF process and window use the dedicated M365 Workbench AppUserModelID'
Assert-True -Condition ($mainSource.Contains('EntraOnlyFilterButton') -and $mainSource.Contains('ManagementStateDescription')) -Name 'Application surfaces and filters Entra-only management mismatches'
Assert-True -Condition ($mainSource.Contains('x:Name="DeviceTableOutline"') -and $mainSource.Contains('x:Name="DeviceCellFrame"') -and $mainSource.Contains('GridLinesVisibility="None"') -and $mainSource.Contains('BorderBrush="#D8E1EC"') -and $mainSource.Contains('BorderThickness="0,0,1,0"')) -Name 'Every device cell owns a deterministic right separator independent of DataGrid focus state'
Assert-True -Condition ($mainSource.Contains('<Style TargetType="DataGridCell">') -and $mainSource.Contains('<Setter Property="BorderThickness" Value="0"/>') -and $mainSource.Contains('<Setter Property="FocusVisualStyle" Value="{x:Null}"/>')) -Name 'Full-row selection does not draw a misleading per-cell focus outline'
Assert-True -Condition ($mainSource.Contains('$window.ShowInTaskbar = $false') -and $mainSource.Contains('$window.ShowActivated = $false') -and $mainSource.Contains('[System.Windows.SystemParameters]::VirtualScreenLeft - $window.Width - 100')) -Name 'Rendered visual previews stay off-screen and out of the taskbar'
Assert-True -Condition ($mainSource.Contains('x:Key="DeviceListScrollThumbBrush"') -and $mainSource.Contains('x:Name="DeviceListVerticalThumb"') -and $mainSource.Contains('x:Name="DeviceListHorizontalThumb"') -and $mainSource.Contains('ScrollBar.PageLeftCommand') -and $mainSource.Contains('ScrollBar.PageRightCommand')) -Name 'Device list uses inset arrow-free scrollbars in both orientations'
Assert-True -Condition ($mainSource.Contains('x:Key="RecoveryKeyPicker"') -and $mainSource.Contains('x:Key="RecoveryKeyPickerItem"') -and $mainSource.Contains('x:Name="RecoveryKeyDropDownSurface"') -and $mainSource.Contains('x:Name="RecoveryKeyPickerChevron"') -and $mainSource.Contains('x:Name="RecoveryKeyScrollThumb"') -and $mainSource.Contains('Style="{StaticResource RecoveryKeyPicker}"') -and -not $mainSource.Contains('DisplayMemberPath="SelectorDisplay"')) -Name 'BitLocker recovery selector uses the dedicated modern picker instead of native Windows chrome'
Assert-True -Condition ($mainSource.Contains('Text="{Binding VolumeDisplay}"') -and $mainSource.Contains('<Run Text="Backed up "/><Run Text="{Binding CreatedDisplay}"/>')) -Name 'Recovery-key choices align volume and backup date as a readable two-line record'
Assert-True -Condition ($mainSource.Contains('x:Name="DetailDeviceName"') -and -not $mainSource.Contains('Text="&#xE770;"')) -Name 'Device detail header does not imply an unavailable chassis type'
Assert-True -Condition ($mainSource.Contains('x:Name="OpenIntuneButton"') -and $mainSource.Contains('x:Name="OpenEntraButton"') -and $mainSource.Contains('Open-SelectedDevicePortal -Portal Intune') -and $mainSource.Contains('Open-SelectedDevicePortal -Portal Entra')) -Name 'Device detail panel exposes both validated admin-center deep links'
$shortcutInstallerSource = [IO.File]::ReadAllText($shortcutInstallerPath)
Assert-True -Condition ($shortcutInstallerSource.Contains('M365 Workbench.lnk') -and $shortcutInstallerSource.Contains('$shortcut.IconLocation = "$launcherPath,0"')) -Name 'Desktop shortcut uses the M365 Workbench name and embedded launcher icon'
Assert-True -Condition ($shortcutInstallerSource.Contains("`$appUserModelId = '$expectedAppUserModelId'") -and $shortcutInstallerSource.Contains('[M365Workbench.WindowsShellIdentity]::SetShortcutAppId($shortcutPath, $appUserModelId)')) -Name 'Desktop shortcut and running app share one Windows shell identity'
Assert-True -Condition ($shortcutInstallerSource.Contains('M365Workbench.Launcher.exe') -and -not $shortcutInstallerSource.Contains('$shortcut.TargetPath = $powerShellAlias')) -Name 'Desktop shortcut starts through the no-console GUI launcher'
Assert-True -Condition (-not $mainSource.Contains('Reachability') -and -not $mainSource.Contains('Header="Online"')) -Name 'Application does not infer device online status outside Intune and Entra data'
Assert-True -Condition ($mainSource.Contains("'BitlockerKey.ReadBasic.All'") -and $mainSource.Contains("'BitlockerKey.Read.All'")) -Name 'BitLocker metadata and key-read scopes are requested together'
$inventoryScriptMatch = [regex]::Match($mainSource, "(?s)\`$inventoryOperationScript = @'\r?\n(?<body>.*?)\r?\n'@")
Assert-True -Condition ($inventoryScriptMatch.Success -and $inventoryScriptMatch.Groups['body'].Value -match 'informationProtection/bitlocker/recoveryKeys') -Name 'Inventory includes BitLocker metadata'
Assert-True -Condition ($inventoryScriptMatch.Success -and $inventoryScriptMatch.Groups['body'].Value -notmatch '(?i)\$select\s*=.*\bkey\b|\$select=[^\r\n\"]*\bkey\b') -Name 'Inventory never requests BitLocker recovery-key secrets'
$keyScriptMatch = [regex]::Match($mainSource, "(?s)\`$bitLockerKeyOperationScript = @'\r?\n(?<body>.*?)\r?\n'@")
Assert-True -Condition ($keyScriptMatch.Success -and $keyScriptMatch.Groups['body'].Value -match '\$select=id,key,deviceId') -Name 'BitLocker secret is requested only by the explicit per-key operation'
$visualPreviewOutput = & $powerShellExecutable -NoLogo -NoProfile -NonInteractive -STA -File $mainScriptPath -DemoMode -RenderPreviewPath $visualPreviewTestPath 2>&1
$visualPreviewExitCode = $LASTEXITCODE
Assert-True -Condition ($visualPreviewExitCode -eq 0 -and (Test-Path -LiteralPath $visualPreviewTestPath -PathType Leaf)) -Name 'Off-screen demo preview renders successfully'
$separatorPixelsAreStable = $false
if ($visualPreviewExitCode -eq 0 -and (Test-Path -LiteralPath $visualPreviewTestPath -PathType Leaf)) {
    Add-Type -AssemblyName System.Drawing
    $visualPreview = [System.Drawing.Bitmap]::FromFile($visualPreviewTestPath)
    try {
        $separatorColor = [System.Drawing.Color]::FromArgb(216, 225, 236).ToArgb()
        $selectionColor = [System.Drawing.Color]::FromArgb(232, 241, 255).ToArgb()
        $selectedRowPixels = @(
            0..($visualPreview.Height - 1) |
                Where-Object { $visualPreview.GetPixel(100, $_).ToArgb() -eq $selectionColor }
        )
        if ($selectedRowPixels.Count -gt 0) {
            $selectedRowTop = $selectedRowPixels[0]
            $selectedRowSampleY = $selectedRowTop + 24
            $headerSampleY = $selectedRowTop - 20
            $headerSeparatorPixels = @(
                100..([Math]::Floor($visualPreview.Width * 0.72)) |
                    Where-Object {
                        $visualPreview.GetPixel($_, $headerSampleY - 8).ToArgb() -eq $separatorColor -and
                        $visualPreview.GetPixel($_, $headerSampleY).ToArgb() -eq $separatorColor -and
                        $visualPreview.GetPixel($_, $headerSampleY + 8).ToArgb() -eq $separatorColor
                    }
            )
            $headerSeparatorStarts = @()
            $previousSeparatorPixel = -2
            foreach ($separatorPixel in $headerSeparatorPixels) {
                if ($separatorPixel -ne ($previousSeparatorPixel + 1)) {
                    $headerSeparatorStarts += $separatorPixel
                }
                $previousSeparatorPixel = $separatorPixel
            }
            $internalSeparatorXs = @($headerSeparatorStarts | Select-Object -First 5)
            $missingSelectedRowSeparators = @(
                $internalSeparatorXs |
                    Where-Object { $visualPreview.GetPixel($_, $selectedRowSampleY).ToArgb() -ne $separatorColor }
            )
            $separatorPixelsAreStable = $internalSeparatorXs.Count -eq 5 -and $missingSelectedRowSeparators.Count -eq 0
        }
    }
    finally {
        $visualPreview.Dispose()
    }
}
Assert-True -Condition $separatorPixelsAreStable -Name 'Focused recovery cell preserves every selected-row column separator in the rendered preview'
$xamlMatch = [regex]::Match($mainSource, "(?s)\`$xaml = @'\r?\n(?<xaml>.*?)\r?\n'@")
Assert-True -Condition $xamlMatch.Success -Name 'Embedded WPF markup is discoverable for validation'
$xamlIsValidXml = $false
if ($xamlMatch.Success) {
    try {
        $null = [xml]$xamlMatch.Groups['xaml'].Value
        $xamlIsValidXml = $true
    }
    catch { }
}
Assert-True -Condition $xamlIsValidXml -Name 'Embedded WPF markup is well-formed XML'

$initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
$runspace.Open()
$powerShell = [PowerShell]::Create()
$powerShell.Runspace = $runspace
$null = $powerShell.AddScript("param(`$Value) [pscustomobject]@{ Kind = 'WorkerTest'; Value = `$Value }")
$null = $powerShell.AddArgument('ok')
$inputCollection = [System.Management.Automation.PSDataCollection[psobject]]::new()
$outputCollection = [System.Management.Automation.PSDataCollection[psobject]]::new()
$async = $powerShell.BeginInvoke[psobject, psobject]($inputCollection, $outputCollection)
$inputCollection.Complete()
$completed = $async.AsyncWaitHandle.WaitOne(5000)
if ($completed) { $null = $powerShell.EndInvoke($async) }
Assert-True -Condition ($completed -and $outputCollection.Count -eq 1 -and $outputCollection[0].Value -eq 'ok') -Name 'Persistent background Graph-worker pattern completes asynchronously'
$inputCollection.Dispose()
$outputCollection.Dispose()
$powerShell.Dispose()
$runspace.Dispose()

Write-Host ''
Write-Host "$($script:Passed) passed; $($script:Failed) failed"
if ($script:Failed -gt 0) {
    exit 1
}
