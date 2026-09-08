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
}
