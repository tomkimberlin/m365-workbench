Set-StrictMode -Version Latest

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function ConvertTo-LapsDateTimeOffset {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [DateTimeOffset]$Value
    }
    catch {
        return $null
    }
}

function Test-UsableEntraDeviceId {
    param(
        [AllowNull()]
        [object]$Value
    )

    $parsed = [Guid]::Empty
    return [Guid]::TryParse([string]$Value, [ref]$parsed) -and $parsed -ne [Guid]::Empty
}

function Get-DeviceAdminPortalUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Intune', 'Entra')]
        [string]$Portal,

        [AllowNull()]
        [object]$Device
    )

    if ($null -eq $Device) {
        return $null
    }

    $propertyName = if ($Portal -eq 'Intune') { 'IntuneDeviceId' } else { 'EntraObjectId' }
    $rawId = [string](Get-PropertyValue -InputObject $Device -Name $propertyName)
    $parsedId = [Guid]::Empty
    if (-not [Guid]::TryParse($rawId, [ref]$parsedId) -or $parsedId -eq [Guid]::Empty) {
        return $null
    }

    $canonicalId = $parsedId.ToString('D')
    $url = if ($Portal -eq 'Intune') {
        "https://intune.microsoft.com/#view/Microsoft_Intune_Devices/DeviceSettingsMenuBlade/~/overview/mdmDeviceId/$canonicalId"
    }
    else {
        "https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DeviceDetailsMenuBlade/~/Properties/objectId/$canonicalId"
    }

    return [Uri]::new($url, [UriKind]::Absolute)
}

function ConvertTo-DisplayDate {
    param(
        [AllowNull()]
        [object]$Value,

        [string]$EmptyText = [string][char]0x2014
    )

    $date = ConvertTo-LapsDateTimeOffset -Value $Value
    if ($null -eq $date) {
        return $EmptyText
    }

    return $date.ToLocalTime().ToString('MMM d, yyyy h:mm tt')
}

function ConvertTo-FriendlyComplianceState {
    param(
        [AllowNull()]
        [object]$Value
    )

    switch (([string]$Value).ToLowerInvariant()) {
        'compliant' { return 'Compliant' }
        'noncompliant' { return 'Not compliant' }
        'conflict' { return 'Conflict' }
        'error' { return 'Error' }
        'ingraceperiod' { return 'Grace period' }
        'unknown' { return 'Unknown' }
        default { return 'Unknown' }
    }
}

function ConvertTo-BitLockerVolumeDisplay {
    param(
        [AllowNull()]
        [object]$Value
    )

    switch (([string]$Value).ToLowerInvariant()) {
        '1' { return 'Operating system volume' }
        'operatingsystemvolume' { return 'Operating system volume' }
        '2' { return 'Fixed data volume' }
        'fixeddatavolume' { return 'Fixed data volume' }
        '3' { return 'Removable data volume' }
        'removabledatavolume' { return 'Removable data volume' }
        default { return 'Unknown volume' }
    }
}

function ConvertTo-TrustTypeDisplay {
    param(
        [AllowNull()]
        [object]$Value
    )

    switch (([string]$Value).ToLowerInvariant()) {
        'azuread' { return 'Microsoft Entra joined' }
        'serverad' { return 'Hybrid Microsoft Entra joined' }
        'workplace' { return 'Microsoft Entra registered' }
        default { return [string][char]0x2014 }
    }
}

function ConvertTo-OwnerTypeDisplay {
    param(
        [AllowNull()]
        [object]$Value
    )

    switch (([string]$Value).ToLowerInvariant()) {
        'company' { return 'Corporate' }
        'personal' { return 'Personal' }
        default { return [string][char]0x2014 }
    }
}

function Test-BitLockerRecoveryKey {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    return [regex]::IsMatch([string]$Value, '^\d{6}(?:-\d{6}){7}$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

function New-LapsDeviceRow {
    param(
        [AllowNull()]
        [object]$ManagedDevice,

        [AllowNull()]
        [object]$LapsMetadata,

        [AllowNull()]
        [object[]]$BitLockerMetadata,

        [AllowNull()]
        [object]$EntraDevice
    )

    $deviceName = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'deviceName')
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        $deviceName = [string](Get-PropertyValue -InputObject $LapsMetadata -Name 'deviceName')
    }
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        $deviceName = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'displayName')
    }
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        $deviceName = 'Unnamed device'
    }

    $entraDeviceId = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'azureADDeviceId')
    if (-not (Test-UsableEntraDeviceId -Value $entraDeviceId)) {
        $entraDeviceId = [string](Get-PropertyValue -InputObject $LapsMetadata -Name 'id')
    }
    if (-not (Test-UsableEntraDeviceId -Value $entraDeviceId)) {
        $entraDeviceId = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'deviceId')
    }
    if (-not (Test-UsableEntraDeviceId -Value $entraDeviceId)) {
        $firstBitLockerItem = @($BitLockerMetadata | Where-Object { $null -ne $_ } | Select-Object -First 1)
        if ($firstBitLockerItem.Count -gt 0) {
            $entraDeviceId = [string](Get-PropertyValue -InputObject $firstBitLockerItem[0] -Name 'deviceId')
        }
    }

    $userDisplayName = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'userDisplayName')
    $userPrincipalName = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'userPrincipalName')
    $primaryUser = $userDisplayName
    if ([string]::IsNullOrWhiteSpace($primaryUser)) {
        $primaryUser = $userPrincipalName
    }
    if ([string]::IsNullOrWhiteSpace($primaryUser)) {
        $primaryUser = 'Unassigned'
    }

    $lastSync = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $ManagedDevice -Name 'lastSyncDateTime')
    $lastBackup = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $LapsMetadata -Name 'lastBackupDateTime')
    $refreshDate = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $LapsMetadata -Name 'refreshDateTime')
    $lapsAvailable = $null -ne $LapsMetadata -and (Test-UsableEntraDeviceId -Value $entraDeviceId)
    $model = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'model')
    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'model')
    }
    $serialNumber = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'serialNumber')
    $osVersion = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'osVersion')
    if ([string]::IsNullOrWhiteSpace($osVersion)) {
        $osVersion = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'operatingSystemVersion')
    }
    $manufacturer = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'manufacturer')
    if ([string]::IsNullOrWhiteSpace($manufacturer)) {
        $manufacturer = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'manufacturer')
    }
    $complianceState = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'complianceState')

    $bitLockerKeys = [System.Collections.Generic.List[object]]::new()
    foreach ($metadata in @($BitLockerMetadata)) {
        if ($null -eq $metadata) {
            continue
        }

        $keyId = [string](Get-PropertyValue -InputObject $metadata -Name 'id')
        $keyDeviceId = [string](Get-PropertyValue -InputObject $metadata -Name 'deviceId')
        if (-not (Test-UsableEntraDeviceId -Value $keyId) -or
            -not (Test-UsableEntraDeviceId -Value $keyDeviceId) -or
            -not [string]::Equals($keyDeviceId, $entraDeviceId, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $created = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $metadata -Name 'createdDateTime')
        $volumeType = Get-PropertyValue -InputObject $metadata -Name 'volumeType'
        $volumeDisplay = ConvertTo-BitLockerVolumeDisplay -Value $volumeType
        $createdDisplay = ConvertTo-DisplayDate -Value $created
        $bitLockerKeys.Add([pscustomobject]@{
            Id              = $keyId
            DeviceId        = $keyDeviceId
            CreatedDateTime = $created
            CreatedDisplay  = $createdDisplay
            VolumeType      = [string]$volumeType
            VolumeDisplay   = $volumeDisplay
            SelectorDisplay = "$volumeDisplay  •  $createdDisplay"
        })
    }
    $orderedBitLockerKeys = @($bitLockerKeys | Sort-Object -Property @{ Expression = {
        if ($null -eq $_.CreatedDateTime) { [DateTimeOffset]::MinValue } else { $_.CreatedDateTime }
    }; Descending = $true })
    $bitLockerAvailable = $orderedBitLockerKeys.Count -gt 0
    $newestBitLockerDate = if ($bitLockerAvailable) { $orderedBitLockerKeys[0].CreatedDateTime } else { $null }

    $operatingSystem = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'operatingSystem')
    if ([string]::IsNullOrWhiteSpace($operatingSystem)) {
        $operatingSystem = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'operatingSystem')
    }
    if ([string]::IsNullOrWhiteSpace($operatingSystem) -and $null -ne $LapsMetadata) {
        $operatingSystem = 'Windows'
    }

    $entraLastSignIn = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $EntraDevice -Name 'approximateLastSignInDateTime')
    $enrolledDate = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $ManagedDevice -Name 'enrolledDateTime')
    $isEncryptedValue = Get-PropertyValue -InputObject $ManagedDevice -Name 'isEncrypted'
    $isEncryptedDisplay = if ($null -eq $isEncryptedValue) { [string][char]0x2014 } elseif ([bool]$isEncryptedValue) { 'Yes' } else { 'No' }
    $managementAgent = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'managementAgent')
    if ([string]::IsNullOrWhiteSpace($managementAgent)) { $managementAgent = [string][char]0x2014 }
    $enrollmentType = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'deviceEnrollmentType')
    if ([string]::IsNullOrWhiteSpace($enrollmentType)) { $enrollmentType = [string][char]0x2014 }

    $isIntuneManaged = $null -ne $ManagedDevice
    $source = if ($isIntuneManaged) { 'Microsoft Intune' } else { 'Microsoft Entra' }
    $managementStateDisplay = if ($isIntuneManaged) { 'Intune managed' } else { 'Entra only' }
    $managementStateDescription = if ($isIntuneManaged) {
        'A matching Microsoft Intune managed-device record was found.'
    }
    else {
        'This device exists in Microsoft Entra with no matching Intune managed-device record. It may be intentionally unmanaged, unenrolled, or stale.'
    }
    $lastSyncDisplay = if ($isIntuneManaged) {
        ConvertTo-DisplayDate -Value $lastSync -EmptyText 'Never'
    }
    else {
        'Not in Intune'
    }
    $searchText = @(
        $deviceName
        $primaryUser
        $userDisplayName
        $userPrincipalName
        $serialNumber
        $model
        $manufacturer
        $osVersion
        $entraDeviceId
        [string](Get-PropertyValue -InputObject $EntraDevice -Name 'id')
        $source
        $managementStateDisplay
        $lastSyncDisplay
        @($orderedBitLockerKeys | ForEach-Object { $_.Id })
    ) -join ' '

    [pscustomobject]@{
        IntuneDeviceId       = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'id')
        EntraDeviceId        = $entraDeviceId
        EntraObjectId        = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'id')
        DeviceName           = $deviceName
        PrimaryUser          = $primaryUser
        UserPrincipalName    = $userPrincipalName
        SerialNumber         = if ([string]::IsNullOrWhiteSpace($serialNumber)) { [string][char]0x2014 } else { $serialNumber }
        Manufacturer         = $manufacturer
        Model                = if ([string]::IsNullOrWhiteSpace($model)) { [string][char]0x2014 } else { $model }
        OperatingSystem      = $operatingSystem
        OSVersion            = $osVersion
        LastSyncDateTime     = $lastSync
        LastSyncDisplay      = $lastSyncDisplay
        ComplianceState      = $complianceState
        ComplianceDisplay    = ConvertTo-FriendlyComplianceState -Value $complianceState
        LapsAvailable        = [bool]$lapsAvailable
        LapsStatus           = if ($lapsAvailable) { 'Ready' } else { 'Not backed up' }
        LastBackupDateTime   = $lastBackup
        LastBackupDisplay    = ConvertTo-DisplayDate -Value $lastBackup
        RefreshDateTime      = $refreshDate
        RefreshDateDisplay   = ConvertTo-DisplayDate -Value $refreshDate
        BitLockerKeys        = $orderedBitLockerKeys
        BitLockerAvailable   = [bool]$bitLockerAvailable
        BitLockerKeyCount    = $orderedBitLockerKeys.Count
        BitLockerStatus      = if ($orderedBitLockerKeys.Count -eq 1) { '1 key' } elseif ($orderedBitLockerKeys.Count -gt 1) { "$($orderedBitLockerKeys.Count) keys" } else { 'No key' }
        BitLockerNewestDateTime = $newestBitLockerDate
        BitLockerNewestDisplay  = ConvertTo-DisplayDate -Value $newestBitLockerDate
        RecoveryAvailable    = [bool]($lapsAvailable -or $bitLockerAvailable)
        TrustType            = [string](Get-PropertyValue -InputObject $EntraDevice -Name 'trustType')
        TrustTypeDisplay     = ConvertTo-TrustTypeDisplay -Value (Get-PropertyValue -InputObject $EntraDevice -Name 'trustType')
        EntraAccountEnabled  = Get-PropertyValue -InputObject $EntraDevice -Name 'accountEnabled'
        EntraLastSignInDateTime = $entraLastSignIn
        EntraLastSignInDisplay  = ConvertTo-DisplayDate -Value $entraLastSignIn
        DeviceOwnerType      = [string](Get-PropertyValue -InputObject $ManagedDevice -Name 'managedDeviceOwnerType')
        DeviceOwnerDisplay   = ConvertTo-OwnerTypeDisplay -Value (Get-PropertyValue -InputObject $ManagedDevice -Name 'managedDeviceOwnerType')
        DeviceEnrollmentType = $enrollmentType
        ManagementAgent     = $managementAgent
        IsEncrypted         = $isEncryptedValue
        IsEncryptedDisplay  = $isEncryptedDisplay
        EnrolledDateTime    = $enrolledDate
        EnrolledDateDisplay = ConvertTo-DisplayDate -Value $enrolledDate
        InventorySource      = $source
        IsIntuneManaged      = $isIntuneManaged
        IsEntraOnly          = -not $isIntuneManaged
        ManagementStateDisplay = $managementStateDisplay
        ManagementStateDescription = $managementStateDescription
        IsStale              = $isIntuneManaged -and $null -ne $lastSync -and $lastSync -lt [DateTimeOffset]::Now.AddDays(-30)
        SearchText           = $searchText.ToLowerInvariant()
    }
}

function Merge-IntuneLapsDeviceData {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$ManagedDevices,

        [AllowNull()]
        [object[]]$LapsMetadata,

        [AllowNull()]
        [object[]]$BitLockerMetadata,

        [AllowNull()]
        [object[]]$EntraDevices
    )

    $lapsById = @{}
    foreach ($metadata in @($LapsMetadata)) {
        if ($null -eq $metadata) {
            continue
        }

        $id = [string](Get-PropertyValue -InputObject $metadata -Name 'id')
        if (Test-UsableEntraDeviceId -Value $id) {
            $lapsById[$id.ToLowerInvariant()] = $metadata
        }
    }

    $entraByDeviceId = @{}
    foreach ($device in @($EntraDevices)) {
        if ($null -eq $device) {
            continue
        }

        $deviceId = [string](Get-PropertyValue -InputObject $device -Name 'deviceId')
        if (Test-UsableEntraDeviceId -Value $deviceId) {
            $entraByDeviceId[$deviceId.ToLowerInvariant()] = $device
        }
    }

    $bitLockerByDeviceId = @{}
    foreach ($metadata in @($BitLockerMetadata)) {
        if ($null -eq $metadata) {
            continue
        }

        $deviceId = [string](Get-PropertyValue -InputObject $metadata -Name 'deviceId')
        if (-not (Test-UsableEntraDeviceId -Value $deviceId)) {
            continue
        }

        $key = $deviceId.ToLowerInvariant()
        if (-not $bitLockerByDeviceId.ContainsKey($key)) {
            $bitLockerByDeviceId[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $bitLockerByDeviceId[$key].Add($metadata)
    }

    # Intune sometimes retains multiple managedDevice records for one Entra device.
    # Keep only the record with the newest check-in so the operator sees one computer.
    $managedByKey = @{}
    foreach ($device in @($ManagedDevices)) {
        if ($null -eq $device) {
            continue
        }

        $operatingSystem = [string](Get-PropertyValue -InputObject $device -Name 'operatingSystem')
        if (-not [string]::Equals($operatingSystem, 'Windows', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $entraId = [string](Get-PropertyValue -InputObject $device -Name 'azureADDeviceId')
        $intuneId = [string](Get-PropertyValue -InputObject $device -Name 'id')
        $key = if (Test-UsableEntraDeviceId -Value $entraId) {
            'entra:' + $entraId.ToLowerInvariant()
        }
        else {
            'intune:' + $intuneId.ToLowerInvariant()
        }

        $candidateDate = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $device -Name 'lastSyncDateTime')
        if (-not $managedByKey.ContainsKey($key)) {
            $managedByKey[$key] = $device
            continue
        }

        $existingDate = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $managedByKey[$key] -Name 'lastSyncDateTime')
        if ($null -ne $candidateDate -and ($null -eq $existingDate -or $candidateDate -gt $existingDate)) {
            $managedByKey[$key] = $device
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $usedDeviceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($device in $managedByKey.Values) {
        $entraId = [string](Get-PropertyValue -InputObject $device -Name 'azureADDeviceId')
        $metadata = $null
        $bitLocker = @()
        $entraDevice = $null
        if (Test-UsableEntraDeviceId -Value $entraId) {
            $metadata = $lapsById[$entraId.ToLowerInvariant()]
            $bitLocker = @($bitLockerByDeviceId[$entraId.ToLowerInvariant()])
            $entraDevice = $entraByDeviceId[$entraId.ToLowerInvariant()]
            $null = $usedDeviceIds.Add($entraId)
        }

        $rows.Add((New-LapsDeviceRow -ManagedDevice $device -LapsMetadata $metadata -BitLockerMetadata $bitLocker -EntraDevice $entraDevice))
    }

    # Include Windows devices present only in Entra, plus recovery records whose
    # corresponding directory object is not returned by the device inventory call.
    $remainingIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $entraByDeviceId.Keys) {
        $entraOs = [string](Get-PropertyValue -InputObject $entraByDeviceId[$id] -Name 'operatingSystem')
        if ([string]::Equals($entraOs, 'Windows', [StringComparison]::OrdinalIgnoreCase) -or $lapsById.ContainsKey($id) -or $bitLockerByDeviceId.ContainsKey($id)) {
            $null = $remainingIds.Add($id)
        }
    }
    foreach ($id in $lapsById.Keys) { $null = $remainingIds.Add($id) }
    foreach ($id in $bitLockerByDeviceId.Keys) { $null = $remainingIds.Add($id) }

    foreach ($id in $remainingIds) {
        if (-not $usedDeviceIds.Contains($id)) {
            $rows.Add((New-LapsDeviceRow `
                -ManagedDevice $null `
                -LapsMetadata $lapsById[$id] `
                -BitLockerMetadata @($bitLockerByDeviceId[$id]) `
                -EntraDevice $entraByDeviceId[$id]))
        }
    }

    return @($rows | Sort-Object DeviceName, UserPrincipalName)
}

function Select-CurrentLapsCredential {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Credentials
    )

    $usable = @(
        $Credentials | Where-Object {
            $null -ne $_ -and
            -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -InputObject $_ -Name 'passwordBase64'))
        }
    )

    if ($usable.Count -eq 0) {
        return $null
    }

    return $usable |
        Sort-Object -Property @{ Expression = {
            $date = ConvertTo-LapsDateTimeOffset -Value (Get-PropertyValue -InputObject $_ -Name 'backupDateTime')
            if ($null -eq $date) { [DateTimeOffset]::MinValue } else { $date }
        }; Descending = $true } |
        Select-Object -First 1
}

function ConvertFrom-LapsPasswordBase64 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PasswordBase64
    )

    $bytes = $null
    $decoded = $null
    try {
        $bytes = [Convert]::FromBase64String($PasswordBase64)

        if ($bytes.Length -eq 0) {
            throw 'The LAPS password payload is empty.'
        }

        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $utf16Le = [Text.UnicodeEncoding]::new($false, $false, $true)
        $utf16Be = [Text.UnicodeEncoding]::new($true, $false, $true)

        $isSafePasswordText = {
            param([AllowNull()][string]$Value)

            if ([string]::IsNullOrEmpty($Value)) {
                return $false
            }

            foreach ($character in $Value.ToCharArray()) {
                if ([char]::IsControl($character)) {
                    return $false
                }
            }

            return $true
        }

        try {
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $decoded = $utf8.GetString($bytes, 3, $bytes.Length - 3).TrimEnd([char]0)
            }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                $decoded = $utf16Le.GetString($bytes, 2, $bytes.Length - 2).TrimEnd([char]0)
            }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                $decoded = $utf16Be.GetString($bytes, 2, $bytes.Length - 2).TrimEnd([char]0)
            }
            else {
                # Current Graph responses can contain UTF-8, while older examples and
                # tenants use UTF-16LE. Prefer valid, control-free UTF-8; UTF-16LE
                # ASCII data naturally contains NUL controls and therefore falls
                # through to the legacy decoder without guessing from byte length.
                try {
                    $decoded = $utf8.GetString($bytes).TrimEnd([char]0)
                }
                catch {
                    $decoded = $null
                }

                if (-not (& $isSafePasswordText $decoded) -and ($bytes.Length % 2) -eq 0) {
                    try {
                        $decoded = $utf16Le.GetString($bytes).TrimEnd([char]0)
                    }
                    catch {
                        $decoded = $null
                    }
                }
            }
        }
        catch {
            $decoded = $null
        }

        if (-not (& $isSafePasswordText $decoded)) {
            throw 'The LAPS password payload could not be decoded safely.'
        }

        return $decoded
    }
    finally {
        $decoded = $null
        if ($null -ne $bytes) {
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
    }
}

function Test-LapsGraphContext {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Context,

        [Parameter(Mandatory)]
        [string]$ExpectedAccount,

        [Parameter(Mandatory)]
        [Guid]$ExpectedTenantId,

        [Parameter(Mandatory)]
        [string[]]$RequiredScopes
    )

    if ($null -eq $Context) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'NoContext'; MissingScopes = @($RequiredScopes) }
    }

    if (-not [string]::Equals([string](Get-PropertyValue -InputObject $Context -Name 'AuthType'), 'Delegated', [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'NotDelegated'; MissingScopes = @($RequiredScopes) }
    }

    $account = [string](Get-PropertyValue -InputObject $Context -Name 'Account')
    if (-not [string]::Equals($account, $ExpectedAccount, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'WrongAccount'; MissingScopes = @() }
    }

    $contextTenantId = [Guid]::Empty
    if (-not [Guid]::TryParse([string](Get-PropertyValue -InputObject $Context -Name 'TenantId'), [ref]$contextTenantId) -or $contextTenantId -ne $ExpectedTenantId) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'WrongTenant'; MissingScopes = @() }
    }

    $granted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in @((Get-PropertyValue -InputObject $Context -Name 'Scopes'))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$scope)) {
            $null = $granted.Add([string]$scope)
        }
    }

    $missing = @($RequiredScopes | Where-Object { -not $granted.Contains($_) })
    return [pscustomobject]@{
        IsValid      = $missing.Count -eq 0
        Reason       = if ($missing.Count -eq 0) { 'Valid' } else { 'MissingScopes' }
        MissingScopes = $missing
    }
}

function Get-DeviceCodeFromMessage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Message
    )

    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $match = [regex]::Match($text, '(?i)enter\s+the\s+code\s+([A-Z0-9]{8,12})\s+to\s+authenticate')
    if (-not $match.Success) {
        return $null
    }

    $urlMatch = [regex]::Match($text, 'https://[^\s]+')
    return [pscustomobject]@{
        UserCode        = $match.Groups[1].Value.ToUpperInvariant()
        VerificationUrl = if ($urlMatch.Success) { $urlMatch.Value.TrimEnd('.', ',') } else { 'https://login.microsoft.com/device' }
    }
}

function Get-FriendlyLapsErrorMessage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ErrorCode,

        [AllowNull()]
        [string]$Message,

        [AllowNull()]
        [Nullable[int]]$StatusCode
    )

    $combined = "$ErrorCode $Message"
    if ($StatusCode -eq 401 -or $combined -match '(?i)authentication|token|sign.?in') {
        return 'Your Microsoft Graph sign-in has expired. Sign in again and retry.'
    }
    if ($StatusCode -eq 403 -or $combined -match '(?i)access.?denied|authorization_requestdenied|insufficient.?privilege') {
        return 'Access was denied. Check the configured Graph recovery permissions and use an eligible Entra role such as Cloud Device Administrator or Intune Administrator.'
    }
    if ($StatusCode -eq 404 -or $combined -match '(?i)not.?found|resource.?not.?found') {
        return 'No current recovery secret was found for the selected record. Refresh the device inventory and retry.'
    }
    if ($StatusCode -eq 429 -or $combined -match '(?i)too.?many.?requests|throttl') {
        return 'Microsoft Graph is temporarily throttling requests. Wait a moment and retry.'
    }
    if ($combined -match '(?i)consent') {
        return "Administrator consent is required for this tool's Microsoft Graph permissions."
    }
    if ($combined -match '(?i)password.?payload|decoded.?safely|passworddecodefailed') {
        return 'Microsoft Graph returned a LAPS password payload that this utility could not decode safely. Close and reopen the updated utility, then retry.'
    }
    if ($combined -match '(?i)48-digit BitLocker|recoverykeyvalidationfailed|different device') {
        return 'Microsoft Graph returned an invalid or mismatched BitLocker recovery-key payload. Refresh the device inventory and retry.'
    }

    return 'Microsoft Graph could not complete the request. Retry, then check the tenant connection and permissions if the problem continues.'
}

Export-ModuleMember -Function @(
    'ConvertFrom-LapsPasswordBase64'
    'Get-DeviceAdminPortalUri'
    'Get-DeviceCodeFromMessage'
    'Get-FriendlyLapsErrorMessage'
    'Merge-IntuneLapsDeviceData'
    'Select-CurrentLapsCredential'
    'Test-BitLockerRecoveryKey'
    'Test-LapsGraphContext'
)
