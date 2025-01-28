param (
    [string]$Action # Accepts "Start" or "Stop"
)


Write-Output "Authenticating using system-assigned managed identity..."
Connect-AzAccount -Identity


if ($Action -eq "Start") {
    Write-Output "Starting the virtual machine..."
    try {
        Start-AzVM -ResourceGroupName "Automation-RG" -Name "dev-vm1" -NoWait
        Write-Output "Successfully started VM "
    } catch {
        Write-Error "Failed to start VM"
    }
}
elseif ($Action -eq "Stop") {
    Write-Output "Stopping the virtual machine..."
    try {
        Stop-AzVM -ResourceGroupName "Automation-RG" -Name "dev-vm1" -Force -NoWait
        Write-Output "Successfully stopped VM..."
    } catch {
        Write-Error "Failed to stop VM"
    }
} else {
    Write-Error "Invalid action specified. Use 'Start' or 'Stop'."
}
