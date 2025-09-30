# Common-Functions.ps1
# Shared functions for Azure Public IP migration automation
# Provides logging, error handling, and utility functions

#Requires -Version 7.0
# Note: Az.Network and Az.Resources modules are checked at runtime instead of #Requires
# This allows for better error messages and graceful handling

# Global variables for logging
$Global:LogFile = ""
$Global:MigrationStartTime = Get-Date
$Global:Config = $null

<#
.SYNOPSIS
    Initializes the migration environment and loads configuration
.DESCRIPTION
    Sets up logging, validates Azure CLI and PowerShell modules, loads configuration file
.PARAMETER ConfigPath
    Path to the migration configuration JSON file
#>
function Initialize-MigrationEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    try {
        # Set up logging
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Global:LogFile = Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Logs\migration_$timestamp.log"
        
        # Create log directory if it doesn't exist
        $logDir = Split-Path $Global:LogFile -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        Write-MigrationLog -Message "=== Azure Public IP Migration - Initialization Started ===" -Level "Information"
        Write-MigrationLog -Message "Log file: $Global:LogFile" -Level "Information"
        
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            throw "PowerShell 7.0 or higher is required. Current version: $($PSVersionTable.PSVersion)`nDownload from: https://github.com/PowerShell/PowerShell/releases"
        }
        Write-MigrationLog -Message "PowerShell version validated: $($PSVersionTable.PSVersion)" -Level "Information"
        
        # Check for required modules with helpful error messages
        $requiredModules = @('Az.Network', 'Az.Resources', 'Az.Accounts')
        $missingModules = @()
        
        foreach ($moduleName in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $moduleName)) {
                $missingModules += $moduleName
                Write-MigrationLog -Message "Module '$moduleName' is not installed" -Level "Warning"
            }
        }
        
        if ($missingModules.Count -gt 0) {
            $installCommand = "Install-Module -Name $($missingModules -join ', ') -Scope CurrentUser -Force"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "MISSING REQUIRED MODULES" -Level "Error"
            Write-MigrationLog -Message "The following PowerShell modules are required but not installed:" -Level "Error"
            foreach ($module in $missingModules) {
                Write-MigrationLog -Message "  - $module" -Level "Error"
            }
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To install the missing modules, run this command:" -Level "Error"
            Write-MigrationLog -Message "  $installCommand" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Missing required PowerShell modules. Install with: $installCommand"
        }
        
        # Import the modules
        foreach ($moduleName in $requiredModules) {
            Import-Module $moduleName -ErrorAction Stop
            Write-MigrationLog -Message "Module loaded: $moduleName" -Level "Information"
        }
        
        # Verify Azure CLI is installed and updated
        try {
            $azVersion = az version --output json 2>$null | ConvertFrom-Json
            if (-not $azVersion) {
                throw "Azure CLI command returned no output"
            }
            $azCliVersion = $azVersion.'azure-cli'
            Write-MigrationLog -Message "Azure CLI version: $azCliVersion" -Level "Information"
            
            # Check minimum version (2.60.0)
            $minVersion = [version]"2.60.0"
            $currentVersion = [version]$azCliVersion
            if ($currentVersion -lt $minVersion) {
                Write-MigrationLog -Message "Azure CLI version $azCliVersion is below minimum required version $minVersion. Please upgrade." -Level "Warning"
                Write-MigrationLog -Message "  Download from: https://docs.microsoft.com/cli/azure/install-azure-cli" -Level "Warning"
            }
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE CLI NOT FOUND" -Level "Error"
            Write-MigrationLog -Message "Azure CLI is required but not installed or not in PATH." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To install Azure CLI:" -Level "Error"
            Write-MigrationLog -Message "  Windows: winget install Microsoft.AzureCLI" -Level "Error"
            Write-MigrationLog -Message "  Or download from: https://docs.microsoft.com/cli/azure/install-azure-cli" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure CLI is not installed or not in PATH. Error: $($_.Exception.Message)"
        }
        
        # Load configuration file
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found at: $ConfigPath"
        }
        
        $Global:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-MigrationLog -Message "Configuration loaded from: $ConfigPath" -Level "Information"
        
        # Validate configuration structure
        $requiredProperties = @('subscriptionId', 'migration', 'publicIps', 'logging', 'validation')
        foreach ($prop in $requiredProperties) {
            if (-not ($Global:Config.PSObject.Properties.Name -contains $prop)) {
                throw "Configuration file is missing required property: $prop"
            }
        }
        
        # Set Azure context
        try {
            Write-MigrationLog -Message "Setting Azure context..." -Level "Information"
            $subscription = Set-AzContext -SubscriptionId $Global:Config.subscriptionId -ErrorAction Stop
            Write-MigrationLog -Message "Azure context set to subscription: $($subscription.Subscription.Name) ($($subscription.Subscription.Id))" -Level "Information"
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE AUTHENTICATION REQUIRED" -Level "Error"
            Write-MigrationLog -Message "Failed to set Azure context. You may need to authenticate." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To authenticate to Azure, run:" -Level "Error"
            Write-MigrationLog -Message "  Connect-AzAccount" -Level "Error"
            Write-MigrationLog -Message "  Set-AzContext -SubscriptionId '$($Global:Config.subscriptionId)'" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure authentication required. Run: Connect-AzAccount"
        }
        
        # Also set Azure CLI context
        try {
            az account set --subscription $Global:Config.subscriptionId 2>$null
            Write-MigrationLog -Message "Azure CLI context set to subscription: $($Global:Config.subscriptionId)" -Level "Information"
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE CLI AUTHENTICATION REQUIRED" -Level "Error"
            Write-MigrationLog -Message "Failed to set Azure CLI context. You may need to authenticate." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To authenticate Azure CLI, run:" -Level "Error"
            Write-MigrationLog -Message "  az login" -Level "Error"
            Write-MigrationLog -Message "  az account set --subscription '$($Global:Config.subscriptionId)'" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure CLI authentication required. Run: az login"
        }
        
        Write-MigrationLog -Message "=== Initialization Completed Successfully ===" -Level "Information"
        return $true
    }
    catch {
        Write-MigrationLog -Message "Initialization failed: $($_.Exception.Message)" -Level "Error"
        Write-MigrationLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level "Error"
        throw
    }
}

<#
.SYNOPSIS
    Writes log messages to file and console
.DESCRIPTION
    Centralized logging function with timestamp, level, and optional error details
.PARAMETER Message
    The log message to write
.PARAMETER Level
    Log level: Information, Warning, Error, Debug
.PARAMETER Exception
    Optional exception object to log details
#>
function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Information',
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Handle empty messages for blank lines
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $logEntry = ""
    }
    else {
        $logEntry = "[$timestamp] [$Level] $Message"
    }
    
    # Add exception details if provided
    if ($Exception) {
        $logEntry += "`r`n    Exception: $($Exception.Message)"
        $logEntry += "`r`n    StackTrace: $($Exception.StackTrace)"
    }
    
    # Write to file if log file is set
    if ($Global:LogFile) {
        try {
            Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch {
            # Silently ignore log file write errors to not break execution
        }
    }
    
    # Write to console based on configuration and level
    if ($Global:Config.logging.enableConsoleOutput -or -not $Global:Config) {
        switch ($Level) {
            'Information' { Write-Host $logEntry -ForegroundColor Cyan }
            'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
            'Error' { Write-Host $logEntry -ForegroundColor Red }
            'Debug' { Write-Host $logEntry -ForegroundColor Gray }
        }
    }
}

<#
.SYNOPSIS
    Discovers all Basic SKU public IPs in the subscription
.DESCRIPTION
    Queries Azure to find all Basic public IPs and their associated resources
.OUTPUTS
    Array of custom objects containing public IP details and associations
#>
function Get-BasicPublicIps {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "Discovering Basic SKU public IPs in subscription..." -Level "Information"
        
        # Use Azure CLI for comprehensive query
        $basicIpsJson = az network public-ip list --query "[?sku.name=='Basic']" --output json
        
        if (-not $basicIpsJson) {
            Write-MigrationLog -Message "No Basic SKU public IPs found in subscription" -Level "Warning"
            return @()
        }
        
        $basicIps = $basicIpsJson | ConvertFrom-Json
        Write-MigrationLog -Message "Found $($basicIps.Count) Basic SKU public IP(s)" -Level "Information"
        
        $ipInventory = @()
        
        foreach ($pip in $basicIps) {
            Write-MigrationLog -Message "Processing public IP: $($pip.name)" -Level "Debug"
            
            # Determine consumer type and ID
            $consumerType = "unattached"
            $consumerId = ""
            $consumerName = ""
            $nicName = ""
            $nicResourceGroup = ""
            
            if ($pip.ipConfiguration) {
                $ipConfigId = $pip.ipConfiguration.id
                
                # Parse the IP configuration ID to determine resource type
                if ($ipConfigId -match '/networkInterfaces/([^/]+)') {
                    $consumerType = "nic"
                    $nicName = $matches[1]
                    $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                    $consumerName = $nicName
                    
                    # Get NIC details to find resource group
                    $nicDetails = az network nic show --ids $consumerId --output json | ConvertFrom-Json
                    $nicResourceGroup = $nicDetails.resourceGroup
                    
                    Write-MigrationLog -Message "  Attached to NIC: $nicName in RG: $nicResourceGroup" -Level "Debug"
                }
                elseif ($ipConfigId -match '/loadBalancers/([^/]+)') {
                    $consumerType = "loadBalancer"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to Load Balancer: $consumerName" -Level "Debug"
                }
                elseif ($ipConfigId -match '/applicationGateways/([^/]+)') {
                    $consumerType = "applicationGateway"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to Application Gateway: $consumerName" -Level "Debug"
                }
                elseif ($ipConfigId -match '/virtualNetworkGateways/([^/]+)') {
                    $consumerType = "vpnGateway"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to VPN Gateway: $consumerName" -Level "Debug"
                }
                else {
                    $consumerType = "other"
                    $consumerId = $ipConfigId
                    Write-MigrationLog -Message "  Attached to unknown resource type: $ipConfigId" -Level "Warning"
                }
            }
            
            # Build inventory object
            $ipInfo = [PSCustomObject]@{
                Name = $pip.name
                ResourceGroup = $pip.resourceGroup
                Location = $pip.location
                IpAddress = if ($pip.ipAddress) { $pip.ipAddress } else { "(not allocated)" }
                AllocationMethod = $pip.publicIPAllocationMethod
                Sku = $pip.sku.name
                ResourceId = $pip.id
                ConsumerType = $consumerType
                ConsumerId = $consumerId
                ConsumerName = $consumerName
                NicName = $nicName
                NicResourceGroup = $nicResourceGroup
                DnsLabel = if ($pip.dnsSettings) { $pip.dnsSettings.domainNameLabel } else { $null }
                DnsFqdn = if ($pip.dnsSettings) { $pip.dnsSettings.fqdn } else { $null }
                Tags = $pip.tags
                MigrationStatus = "pending"
                StandardIpName = "$($pip.name)-std"
                StandardIpAddress = ""
                StandardIpResourceId = ""
                MigrationTimestamp = ""
                Notes = ""
            }
            
            $ipInventory += $ipInfo
        }
        
        Write-MigrationLog -Message "Basic IP inventory completed: $($ipInventory.Count) IPs cataloged" -Level "Information"
        return $ipInventory
    }
    catch {
        Write-MigrationLog -Message "Failed to discover Basic public IPs: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Exports migration inventory to CSV
.DESCRIPTION
    Saves the public IP inventory to a CSV file for tracking and reporting
.PARAMETER Inventory
    Array of public IP inventory objects
.PARAMETER OutputPath
    Path for the output CSV file
#>
function Export-MigrationInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Inventory,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        Write-MigrationLog -Message "Exporting migration inventory to: $OutputPath" -Level "Information"
        
        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Export to CSV with all properties
        $Inventory | Export-Csv -Path $OutputPath -NoTypeInformation -Force
        
        Write-MigrationLog -Message "Inventory exported successfully: $($Inventory.Count) records written" -Level "Information"
        
        # Also create a summary file
        $summaryPath = $OutputPath -replace '\.csv$', '_summary.txt'
        $summary = @"
Azure Public IP Migration Inventory Summary
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Subscription: $($Global:Config.subscriptionName) ($($Global:Config.subscriptionId))

Total Basic Public IPs: $($Inventory.Count)

By Consumer Type:
$($Inventory | Group-Object ConsumerType | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

By Location:
$($Inventory | Group-Object Location | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

By Migration Status:
$($Inventory | Group-Object MigrationStatus | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

Full details available in: $OutputPath
"@
        
        $summary | Out-File -FilePath $summaryPath -Force
        Write-MigrationLog -Message "Summary file created: $summaryPath" -Level "Information"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to export inventory: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

# Export module members - make functions available to importing scripts
Export-ModuleMember -Function @(
    'Initialize-MigrationEnvironment',
    'Write-MigrationLog',
    'Get-BasicPublicIps',
    'Export-MigrationInventory'
)

<#
.SYNOPSIS
    Gets all accessible Azure subscriptions
.DESCRIPTION
    Retrieves list of subscriptions based on configuration settings
.OUTPUTS
    Array of subscription objects with Id and Name
#>
function Get-AzureSubscriptions {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "Retrieving Azure subscriptions..." -Level "Information"
        
        # Get all subscriptions
        $allSubscriptions = az account list --output json | ConvertFrom-Json
        
        if (-not $allSubscriptions -or $allSubscriptions.Count -eq 0) {
            Write-MigrationLog -Message "No Azure subscriptions found or accessible" -Level "Warning"
            return @()
        }
        
        Write-MigrationLog -Message "Found $($allSubscriptions.Count) total subscription(s)" -Level "Information"
        
        # Filter based on configuration
        if (-not $Global:Config.scanAllSubscriptions) {
            # Use only the configured subscription
            $targetSub = $allSubscriptions | Where-Object { $_.id -eq $Global:Config.subscriptionId }
            if ($targetSub) {
                Write-MigrationLog -Message "Using single subscription: $($targetSub.name) ($($targetSub.id))" -Level "Information"
                return @($targetSub)
            }
            else {
                Write-MigrationLog -Message "Configured subscription not found: $($Global:Config.subscriptionId)" -Level "Error"
                return @()
            }
        }
        
        # Filter subscriptions based on include/exclude lists
        $filteredSubs = $allSubscriptions
        
        # Apply include filter if specified
        if ($Global:Config.includeSubscriptions -and $Global:Config.includeSubscriptions.Count -gt 0) {
            $filteredSubs = $filteredSubs | Where-Object { 
                $_.id -in $Global:Config.includeSubscriptions -or 
                $_.name -in $Global:Config.includeSubscriptions 
            }
            Write-MigrationLog -Message "Applied include filter: $($filteredSubs.Count) subscription(s) match" -Level "Information"
        }
        
        # Apply exclude filter if specified
        if ($Global:Config.excludeSubscriptions -and $Global:Config.excludeSubscriptions.Count -gt 0) {
            $filteredSubs = $filteredSubs | Where-Object { 
                $_.id -notin $Global:Config.excludeSubscriptions -and 
                $_.name -notin $Global:Config.excludeSubscriptions 
            }
            Write-MigrationLog -Message "Applied exclude filter: $($filteredSubs.Count) subscription(s) remaining" -Level "Information"
        }
        
        Write-MigrationLog -Message "Will scan $($filteredSubs.Count) subscription(s) for Basic public IPs" -Level "Information"
        
        foreach ($sub in $filteredSubs) {
            Write-MigrationLog -Message "  - $($sub.name) ($($sub.id))" -Level "Information"
        }
        
        return $filteredSubs
    }
    catch {
        Write-MigrationLog -Message "Failed to retrieve subscriptions: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Sets the active Azure subscription context
.DESCRIPTION
    Switches both Azure CLI and PowerShell contexts to specified subscription
.PARAMETER SubscriptionId
    The subscription ID to set as active
.PARAMETER SubscriptionName
    The subscription name (for logging)
#>
function Set-AzureSubscriptionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionName = ""
    )
    
    try {
        $displayName = if ($SubscriptionName) { "$SubscriptionName ($SubscriptionId)" } else { $SubscriptionId }
        Write-MigrationLog -Message "Setting subscription context to: $displayName" -Level "Information"
        
        # Set PowerShell context
        $subscription = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        Write-MigrationLog -Message "  PowerShell context set" -Level "Debug"
        
        # Set Azure CLI context
        az account set --subscription $SubscriptionId 2>$null
        Write-MigrationLog -Message "  Azure CLI context set" -Level "Debug"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to set subscription context: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Discovers all Basic SKU public IPs across subscriptions
.DESCRIPTION
    Queries Azure to find all Basic public IPs in specified subscriptions
.PARAMETER Subscriptions
    Array of subscription objects to scan
.OUTPUTS
    Array of custom objects containing public IP details and associations
#>
function Get-BasicPublicIpsMultiSubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Subscriptions
    )
    
    try {
        Write-MigrationLog -Message "=== Multi-Subscription Discovery ===" -Level "Information"
        Write-MigrationLog -Message "Scanning $($Subscriptions.Count) subscription(s)" -Level "Information"
        
        $allInventory = @()
        $subCount = 0
        
        foreach ($sub in $Subscriptions) {
            $subCount++
            Write-MigrationLog -Message "`n--- Subscription $subCount of $($Subscriptions.Count) ---" -Level "Information"
            Write-MigrationLog -Message "Name: $($sub.name)" -Level "Information"
            Write-MigrationLog -Message "ID: $($sub.id)" -Level "Information"
            
            # Set context to this subscription
            Set-AzureSubscriptionContext -SubscriptionId $sub.id -SubscriptionName $sub.name
            
            # Discover Basic IPs in this subscription
            Write-MigrationLog -Message "Discovering Basic SKU public IPs..." -Level "Information"
            
            $basicIpsJson = az network public-ip list --query "[?sku.name=='Basic']" --output json
            
            if (-not $basicIpsJson) {
                Write-MigrationLog -Message "No Basic SKU public IPs found in this subscription" -Level "Information"
                continue
            }
            
            $basicIps = $basicIpsJson | ConvertFrom-Json
            Write-MigrationLog -Message "Found $($basicIps.Count) Basic SKU public IP(s)" -Level "Information"
            
            foreach ($pip in $basicIps) {
                Write-MigrationLog -Message "  Processing: $($pip.name)" -Level "Debug"
                
                # Determine consumer type and ID
                $consumerType = "unattached"
                $consumerId = ""
                $consumerName = ""
                $nicName = ""
                $nicResourceGroup = ""
                
                if ($pip.ipConfiguration) {
                    $ipConfigId = $pip.ipConfiguration.id
                    
                    # Parse the IP configuration ID to determine resource type
                    if ($ipConfigId -match '/networkInterfaces/([^/]+)') {
                        $consumerType = "nic"
                        $nicName = $matches[1]
                        $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                        $consumerName = $nicName
                        
                        # Get NIC details to find resource group
                        $nicDetails = az network nic show --ids $consumerId --output json | ConvertFrom-Json
                        $nicResourceGroup = $nicDetails.resourceGroup
                        
                        Write-MigrationLog -Message "    Attached to NIC: $nicName in RG: $nicResourceGroup" -Level "Debug"
                    }
                    elseif ($ipConfigId -match '/loadBalancers/([^/]+)') {
                        $consumerType = "loadBalancer"
                        $consumerName = $matches[1]
                        $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                        Write-MigrationLog -Message "    Attached to Load Balancer: $consumerName" -Level "Debug"
                    }
                    elseif ($ipConfigId -match '/applicationGateways/([^/]+)') {
                        $consumerType = "applicationGateway"
                        $consumerName = $matches[1]
                        $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                        Write-MigrationLog -Message "    Attached to Application Gateway: $consumerName" -Level "Debug"
                    }
                    elseif ($ipConfigId -match '/virtualNetworkGateways/([^/]+)') {
                        $consumerType = "vpnGateway"
                        $consumerName = $matches[1]
                        $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                        Write-MigrationLog -Message "    Attached to VPN Gateway: $consumerName" -Level "Debug"
                    }
                    else {
                        $consumerType = "other"
                        $consumerId = $ipConfigId
                        Write-MigrationLog -Message "    Attached to unknown resource type: $ipConfigId" -Level "Warning"
                    }
                }
                
                # Build inventory object with subscription information
                $ipInfo = [PSCustomObject]@{
                    SubscriptionId = $sub.id
                    SubscriptionName = $sub.name
                    Name = $pip.name
                    ResourceGroup = $pip.resourceGroup
                    Location = $pip.location
                    IpAddress = if ($pip.ipAddress) { $pip.ipAddress } else { "(not allocated)" }
                    AllocationMethod = $pip.publicIPAllocationMethod
                    Sku = $pip.sku.name
                    ResourceId = $pip.id
                    ConsumerType = $consumerType
                    ConsumerId = $consumerId
                    ConsumerName = $consumerName
                    NicName = $nicName
                    NicResourceGroup = $nicResourceGroup
                    DnsLabel = if ($pip.dnsSettings) { $pip.dnsSettings.domainNameLabel } else { $null }
                    DnsFqdn = if ($pip.dnsSettings) { $pip.dnsSettings.fqdn } else { $null }
                    Tags = $pip.tags
                    MigrationStatus = "pending"
                    StandardIpName = "$($pip.name)-std"
                    StandardIpAddress = ""
                    StandardIpResourceId = ""
                    MigrationTimestamp = ""
                    Notes = ""
                }
                
                $allInventory += $ipInfo
            }
            
            Write-MigrationLog -Message "Subscription scan complete: $($basicIps.Count) IPs cataloged" -Level "Information"
        }
        
        Write-MigrationLog -Message "`n=== Multi-Subscription Discovery Complete ===" -Level "Information"
        Write-MigrationLog -Message "Total Basic IPs across all subscriptions: $($allInventory.Count)" -Level "Information"
        
        # Group by subscription for summary
        $bySubscription = $allInventory | Group-Object SubscriptionName
        Write-MigrationLog -Message "`nBy Subscription:" -Level "Information"
        foreach ($group in $bySubscription) {
            Write-MigrationLog -Message "  $($group.Name): $($group.Count) IPs" -Level "Information"
        }
        
        return $allInventory
    }
    catch {
        Write-MigrationLog -Message "Failed to discover Basic public IPs across subscriptions: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Creates a Standard SKU public IP in the appropriate subscription
.DESCRIPTION
    Creates a new Standard SKU public IP with specified configuration, ensuring correct subscription context
.PARAMETER Name
    Name for the new Standard public IP
.PARAMETER ResourceGroup
    Resource group for the new IP
.PARAMETER Location
    Azure region for the new IP
.PARAMETER SubscriptionId
    Subscription ID where the IP should be created
.OUTPUTS
    Custom object with new public IP details
#>
function New-StandardPublicIpWithSubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    try {
        # Set correct subscription context
        Set-AzureSubscriptionContext -SubscriptionId $SubscriptionId
        
        Write-MigrationLog -Message "Creating Standard public IP: $Name in subscription: $SubscriptionId" -Level "Information"
        Write-MigrationLog -Message "  Resource Group: $ResourceGroup" -Level "Debug"
        Write-MigrationLog -Message "  Location: $Location" -Level "Debug"
        
        # Build creation command with all parameters
        $createParams = @(
            "--name", $Name,
            "--resource-group", $ResourceGroup,
            "--location", $Location,
            "--sku", "Standard",
            "--allocation-method", $Global:Config.migration.standardSkuAllocationMethod,
            "--version", $Global:Config.migration.standardSkuVersion,
            "--tags", "$($Global:Config.migration.tagKey)=$($Global:Config.migration.tagValue)",
            "--subscription", $SubscriptionId,
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
            SubscriptionId = $SubscriptionId
        }
    }
    catch {
        Write-MigrationLog -Message "Failed to create Standard public IP '$Name': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Adds a secondary IP configuration to a NIC with subscription context
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
.PARAMETER SubscriptionId
    Subscription ID where the NIC exists
#>
function Add-SecondaryIpConfigToNicWithSubscription {
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
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    try {
        # Set correct subscription context
        Set-AzureSubscriptionContext -SubscriptionId $SubscriptionId
        
        Write-MigrationLog -Message "Adding secondary IP config '$IpConfigName' to NIC: $NicName" -Level "Information"
        Write-MigrationLog -Message "  Subscription: $SubscriptionId" -Level "Debug"
        
        # Get current NIC details to validate state
        $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --subscription $SubscriptionId --output json
        $nic = $nicJson | ConvertFrom-Json
        
        # Check if IP config already exists
        $existingConfig = $nic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
        if ($existingConfig) {
            Write-MigrationLog -Message "  IP configuration '$IpConfigName' already exists on NIC. Skipping creation." -Level "Warning"
            return $true
        }
        
        # Create the IP configuration
        $result = az network nic ip-config create `
            --resource-group $NicResourceGroup `
            --nic-name $NicName `
            --name $IpConfigName `
            --public-ip-address $PublicIpName `
            --subscription $SubscriptionId `
            --output json
        
        if (-not $result) {
            throw "Failed to create IP configuration. Azure CLI returned no output."
        }
        
        Write-MigrationLog -Message "  Secondary IP configuration added successfully" -Level "Information"
        
        # Verify the configuration was added
        $updatedNicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --subscription $SubscriptionId --output json
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

<#
.SYNOPSIS
    Removes Basic public IP from NIC and deletes the resource with subscription context
.DESCRIPTION
    Safely removes the Basic IP configuration and deletes the public IP after migration soak period
.PARAMETER BasicIpName
    Name of the Basic public IP to remove
.PARAMETER BasicIpResourceGroup
    Resource group containing the Basic IP
.PARAMETER SubscriptionId
    Subscription ID where the IP exists
.PARAMETER NicName
    Name of the NIC to remove IP config from
.PARAMETER NicResourceGroup
    Resource group containing the NIC
.PARAMETER IpConfigName
    Name of the IP configuration to remove
#>
function Remove-BasicPublicIpWithSubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasicIpName,
        
        [Parameter(Mandatory = $true)]
        [string]$BasicIpResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [string]$NicName,
        
        [Parameter(Mandatory = $false)]
        [string]$NicResourceGroup,
        
        [Parameter(Mandatory = $false)]
        [string]$IpConfigName
    )
    
    try {
        # Set correct subscription context
        Set-AzureSubscriptionContext -SubscriptionId $SubscriptionId
        
        Write-MigrationLog -Message "Removing Basic public IP: $BasicIpName" -Level "Information"
        Write-MigrationLog -Message "  Subscription: $SubscriptionId" -Level "Debug"
        
        # If attached to NIC, remove IP configuration first
        if ($NicName -and $IpConfigName) {
            Write-MigrationLog -Message "  Removing IP configuration '$IpConfigName' from NIC: $NicName" -Level "Information"
            
            # Get NIC to find the IP config
            $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --subscription $SubscriptionId --output json
            $nic = $nicJson | ConvertFrom-Json
            
            $ipConfig = $nic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
            
            if ($ipConfig) {
                # Remove the IP configuration
                az network nic ip-config delete `
                    --resource-group $NicResourceGroup `
                    --nic-name $NicName `
                    --name $IpConfigName `
                    --subscription $SubscriptionId `
                    --output none 2>$null
                
                Write-MigrationLog -Message "  IP configuration removed from NIC" -Level "Information"
            }
            else {
                Write-MigrationLog -Message "  IP configuration '$IpConfigName' not found on NIC" -Level "Warning"
            }
        }
        
        # Delete the Basic public IP resource
        Write-MigrationLog -Message "  Deleting Basic public IP resource: $BasicIpName" -Level "Information"
        
        az network public-ip delete `
            --name $BasicIpName `
            --resource-group $BasicIpResourceGroup `
            --subscription $SubscriptionId `
            --output none
        
        Write-MigrationLog -Message "  Basic public IP deleted successfully" -Level "Information"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to remove Basic public IP '$BasicIpName': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}


# Export module members - make functions available to importing scripts
Export-ModuleMember -Function @(
    'Initialize-MigrationEnvironment',
    'Write-MigrationLog',
    'Get-BasicPublicIps',
    'Export-MigrationInventory',
    'Get-AzureSubscriptions',
    'Set-AzureSubscriptionContext',
    'Get-BasicPublicIpsMultiSubscription',
    'New-StandardPublicIpWithSubscription',
    'Add-SecondaryIpConfigToNicWithSubscription',
    'Remove-BasicPublicIpWithSubscription'
)
