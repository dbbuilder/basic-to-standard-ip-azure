
<#
.SYNOPSIS
    Creates a Standard SKU public IP with dry run support
.DESCRIPTION
    Creates a new Standard SKU public IP with specified configuration
.PARAMETER Name
    Name for the new Standard public IP
.PARAMETER ResourceGroup
    Resource group for the new IP
.PARAMETER Location
    Azure region for the new IP
.PARAMETER DryRun
    If specified, simulates the operation without creating resources
.OUTPUTS
    Custom object with new public IP details (or simulated details in dry run)
#>
function New-StandardPublicIp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    try {
        Write-MigrationLog -Message "Creating Standard public IP: $Name in RG: $ResourceGroup, Location: $Location" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "  [DRY RUN] Would create Standard public IP with:" -Level "Warning"
            Write-MigrationLog -Message "    Name: $Name" -Level "Warning"
            Write-MigrationLog -Message "    Resource Group: $ResourceGroup" -Level "Warning"
            Write-MigrationLog -Message "    Location: $Location" -Level "Warning"
            Write-MigrationLog -Message "    SKU: Standard" -Level "Warning"
            Write-MigrationLog -Message "    Allocation: $($Global:Config.migration.standardSkuAllocationMethod)" -Level "Warning"
            Write-MigrationLog -Message "    Version: $($Global:Config.migration.standardSkuVersion)" -Level "Warning"
            
            if ($Global:Config.migration.useZones -and $Global:Config.migration.zones.Count -gt 0) {
                Write-MigrationLog -Message "    Zones: $($Global:Config.migration.zones -join ', ')" -Level "Warning"
            }
            
            Write-MigrationLog -Message "    Tags: $($Global:Config.migration.tagKey)=$($Global:Config.migration.tagValue)" -Level "Warning"
            
            # Return simulated object
            return [PSCustomObject]@{
                Name = $Name
                ResourceGroup = $ResourceGroup
                IpAddress = "203.0.113.100"  # Simulated IP (TEST-NET-3 range)
                ResourceId = "/subscriptions/$($Global:Config.subscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.Network/publicIPAddresses/$Name"
                Location = $Location
                Sku = "Standard"
            }
        }
        
        # Build creation command with all parameters
        $createParams = @(
            "--name", $Name,
            "--resource-group", $ResourceGroup,
            "--location", $Location,
            "--sku", "Standard",
            "--allocation-method", $Global:Config.migration.standardSkuAllocationMethod,
            "--version", $Global:Config.migration.standardSkuVersion,
            "--tags", "$($Global:Config.migration.tagKey)=$($Global:Config.migration.tagValue)",
            "--output", "json"
        )
        
        # Add zones if configured
        if ($Global:Config.migration.useZones -and $Global:Config.migration.zones.Count -gt 0) {
            foreach ($zone in $Global:Config.migration.zones) {
                $createParams += "--zone"
                $createParams += $zone
            }
            Write-MigrationLog -Message "  Configuring zones: $($Global:Config.migration.zones -join ', ')" -Level "Debug"
        }
        
        # Execute creation
        $newIpJson = az network public-ip create @createParams
        
        if (-not $newIpJson) {
            throw "Failed to create Standard public IP: $Name. Azure CLI returned no output."
        }
        
        $newIp = $newIpJson | ConvertFrom-Json
        
        Write-MigrationLog -Message "  Standard IP created successfully" -Level "Information"
        Write-MigrationLog -Message "  IP Address: $($newIp.publicIp.ipAddress)" -Level "Information"
        Write-MigrationLog -Message "  Resource ID: $($newIp.publicIp.id)" -Level "Debug"
        
        return [PSCustomObject]@{
            Name = $newIp.publicIp.name
            ResourceGroup = $ResourceGroup
            IpAddress = $newIp.publicIp.ipAddress
            ResourceId = $newIp.publicIp.id
            Location = $newIp.publicIp.location
            Sku = $newIp.publicIp.sku.name
        }
    }
    catch {
        Write-MigrationLog -Message "Failed to create Standard public IP '$Name': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Adds a secondary IP configuration to a NIC with Standard public IP (with dry run support)
.DESCRIPTION
    Creates a new IP configuration on an existing NIC and associates the Standard public IP
.PARAMETER NicName
    Name of the network interface
.PARAMETER NicResourceGroup
    Resource group containing the NIC
.PARAMETER IpConfigName
    Name for the new IP configuration
.PARAMETER PublicIpName
    Name of the Standard public IP to associate
.PARAMETER DryRun
    If specified, simulates the operation without making changes
#>
function Add-SecondaryIpConfigToNic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NicName,
        
        [Parameter(Mandatory = $true)]
        [string]$NicResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$IpConfigName,
        
        [Parameter(Mandatory = $true)]
        [string]$PublicIpName,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    try {
        Write-MigrationLog -Message "Adding secondary IP config '$IpConfigName' to NIC: $NicName" -Level "Information"
        
        # Get current NIC details to validate state
        $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
        $nic = $nicJson | ConvertFrom-Json
        
        # Check if IP config already exists
        $existingConfig = $nic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
        if ($existingConfig) {
            Write-MigrationLog -Message "  IP configuration '$IpConfigName' already exists on NIC. Skipping creation." -Level "Warning"
            return $true
        }
        
        if ($DryRun) {
            Write-MigrationLog -Message "  [DRY RUN] Would add secondary IP configuration:" -Level "Warning"
            Write-MigrationLog -Message "    NIC Name: $NicName" -Level "Warning"
            Write-MigrationLog -Message "    NIC Resource Group: $NicResourceGroup" -Level "Warning"
            Write-MigrationLog -Message "    IP Config Name: $IpConfigName" -Level "Warning"
            Write-MigrationLog -Message "    Public IP Name: $PublicIpName" -Level "Warning"
            Write-MigrationLog -Message "    Current IP Configs: $($nic.ipConfigurations.Count)" -Level "Warning"
            Write-MigrationLog -Message "    Result: NIC would have $($nic.ipConfigurations.Count + 1) IP configurations" -Level "Warning"
            return $true
        }
        
        # Create the IP configuration
        $result = az network nic ip-config create `
            --resource-group $NicResourceGroup `
            --nic-name $NicName `
            --name $IpConfigName `
            --public-ip-address $PublicIpName `
            --output json
        
        if (-not $result) {
            throw "Failed to create IP configuration. Azure CLI returned no output."
        }
        
        Write-MigrationLog -Message "  Secondary IP configuration added successfully" -Level "Information"
        
        # Verify the configuration was added
        $updatedNicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
        $updatedNic = $updatedNicJson | ConvertFrom-Json
        $verifyConfig = $updatedNic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
        
        if ($verifyConfig) {
            Write-MigrationLog -Message "  Verified IP configuration is present on NIC" -Level "Debug"
            return $true
        }
        else {
            throw "IP configuration was created but verification failed"
        }
    }
    catch {
        Write-MigrationLog -Message "Failed to add secondary IP config to NIC '$NicName': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}
