@{
    # Use either the verified tenant domain or tenant object ID for Graph sign-in.
    TenantId                  = 'contoso.onmicrosoft.com'

    # Used to reject a cached Graph context from another tenant.
    TenantObjectId            = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'

    # Used to reject a cached daily-user or unintended administrator context.
    ExpectedAccount           = 'laps-admin@contoso.onmicrosoft.com'

    RequiredScopes            = @(
        'Device.Read.All'
        'DeviceManagementManagedDevices.Read.All'
        'DeviceLocalCredential.Read.All'
        'BitlockerKey.ReadBasic.All'
        'BitlockerKey.Read.All'
    )

    GraphModuleMinimumVersion = '2.38.0'
    ClipboardClearSeconds     = 45
    RevealSeconds             = 20
    OnlyRecoveryReadyByDefault = $true
}
