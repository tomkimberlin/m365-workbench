# Exercise production inventory/filter functions with real WPF event dispatch and
# fictional metadata only. No window, authentication, or tenant connection is used.
& {
    Add-Type -AssemblyName PresentationFramework
    foreach ($functionName in @('Update-FilteredCount', 'Refresh-DeviceFilter', 'Set-DeviceInventory')) {
        $functionAst = $mainAst.Find({ param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true)
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    function Get-SelectedDevice { return $DeviceGrid.SelectedItem }
    function Update-DetailPanel { }
    $DeviceGrid = [System.Windows.Controls.DataGrid]::new()
    $DeviceGrid.CanUserAddRows = $false
    $SearchBox = [System.Windows.Controls.TextBox]::new()
    $OnlyReadyCheckBox = [System.Windows.Controls.CheckBox]::new()
    $EntraOnlyCheckBox = [System.Windows.Controls.CheckBox]::new()
    $DeviceCountText = [System.Windows.Controls.TextBlock]::new()
    $EntraOnlyFilterCount = [System.Windows.Controls.TextBlock]::new()
    $EntraOnlyFilterContainer = [System.Windows.Controls.Border]::new()
    $EmptyStateTitle = [System.Windows.Controls.TextBlock]::new()
    $EmptyStateDescription = [System.Windows.Controls.TextBlock]::new()
    $EmptyState = [System.Windows.Controls.Border]::new()
    $LoadingOverlay = [System.Windows.Controls.Border]::new()
    $RefreshButtonText = [System.Windows.Controls.TextBlock]::new()
    $script:DeviceView = $null
    $OnlyReadyCheckBox.IsChecked = $true
    $EntraOnlyCheckBox.Add_Checked({ Refresh-DeviceFilter })
    $EntraOnlyCheckBox.Add_Unchecked({ Refresh-DeviceFilter })
    $managed = [pscustomobject]@{
        EntraDeviceId='11111111-1111-4111-8111-111111111111'; SearchText='demo-device-alpha'
        IsEntraOnly=$false; RecoveryAvailable=$true; LapsAvailable=$true; BitLockerAvailable=$true
    }
    $entra = [pscustomobject]@{
        EntraDeviceId='22222222-2222-4222-8222-222222222222'; SearchText='demo-device-bravo'
        IsEntraOnly=$true; RecoveryAvailable=$true; LapsAvailable=$true; BitLockerAvailable=$false
    }
    Set-DeviceInventory @($managed, $entra)
    $EntraOnlyCheckBox.IsChecked = $true
    Assert-True -Condition ($script:DeviceView.Count -eq 1 -and $DeviceGrid.SelectedItem -eq $entra) -Name 'Entra-only filter starts with the matching synthetic device selected'
    Set-DeviceInventory @($managed)
    Assert-True -Condition ($EntraOnlyCheckBox.IsChecked -eq $false -and $EntraOnlyFilterContainer.Visibility -eq 'Collapsed') -Name 'Refresh with no Entra-only devices clears and hides the unavailable filter'
    Assert-True -Condition ($script:DeviceView.Count -eq 1 -and $DeviceCountText.Text -like '1 shown*' -and $EmptyState.Visibility -eq 'Collapsed' -and $DeviceGrid.SelectedItem -eq $managed) -Name 'Refresh keeps rows, displayed count, empty overlay, and selection consistent after clearing Entra-only'

    Set-DeviceInventory @($managed, $entra)
    $EntraOnlyCheckBox.IsChecked = $true
    $SearchBox.Text = 'does-not-match'
    Set-DeviceInventory @($managed)
    Assert-True -Condition ($script:DeviceView.Count -eq 0 -and $DeviceCountText.Text -like '0 shown*' -and $EmptyState.Visibility -eq 'Visible' -and $null -eq $DeviceGrid.SelectedItem) -Name 'Clearing Entra-only preserves an independent search and its genuine empty state'

    Set-DeviceInventory -Devices @()
    Assert-True -Condition ($script:DeviceView.IsEmpty -and $script:AllDevices.Count -eq 0 -and $null -eq $DeviceGrid.SelectedItem -and $EmptyState.Visibility -eq 'Visible' -and $EmptyStateTitle.Text -eq 'No Windows computers found' -and $DeviceCountText.Text -like '0 shown*') -Name 'A successful empty inventory replaces old rows with a consistent empty state without throwing'
    $SearchBox.Clear()
    Set-DeviceInventory -Devices @($managed)
    Assert-True -Condition ($script:DeviceView.Count -eq 1 -and $DeviceGrid.SelectedItem -eq $managed -and $EmptyState.Visibility -eq 'Collapsed') -Name 'A later successful inventory recovers from the empty state'

    # Measure representative inventory work without a machine-dependent time assertion.
    $SearchBox.Clear()
    $inventoryFixture = @(for ($index=0; $index -lt 5000; $index++) {
        [pscustomobject]@{ EntraDeviceId=('00000000-0000-4000-8000-{0:d12}' -f $index); SearchText=('demo-device-{0:d5}' -f $index); IsEntraOnly=($index % 10 -eq 0); RecoveryAvailable=$true; LapsAvailable=$true; BitLockerAvailable=$true }
    })
    $loadWatch = [Diagnostics.Stopwatch]::StartNew()
    Set-DeviceInventory $inventoryFixture
    $loadWatch.Stop()
    $searchWatch = [Diagnostics.Stopwatch]::StartNew()
    $SearchBox.Text = '  DEMO-DEVICE-04999  '
    Refresh-DeviceFilter
    $searchWatch.Stop()
    Assert-True -Condition ($script:DeviceView.Count -eq 1 -and $DeviceGrid.SelectedItem.SearchText -eq 'demo-device-04999') -Name '5,000-row search normalizes text and selects the correct match'
    Assert-True -Condition ($script:InventoryCounts.Laps -eq 5000 -and $script:InventoryCounts.EntraOnly -eq 500) -Name '5,000-row inventory totals remain correct'
    $previous = $DeviceGrid.SelectedItem.EntraDeviceId
    Set-DeviceInventory $inventoryFixture
    Assert-True -Condition ($DeviceGrid.SelectedItem.EntraDeviceId -eq $previous) -Name 'Inventory refresh preserves a still-visible selected device'
    Write-Host ('PERF  5,000 rows: load {0}ms; search {1}ms' -f $loadWatch.ElapsedMilliseconds,$searchWatch.ElapsedMilliseconds)
}
