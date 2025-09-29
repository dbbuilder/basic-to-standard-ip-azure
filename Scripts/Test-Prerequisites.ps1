# Test-Prerequisites.ps1
# Validates all prerequisites for Azure IP Migration Tool

#Requires -Version 7.0

<#
.SYNOPSIS
    Tests and validates all prerequisites for the migration tool
.DESCRIPTION
    Checks PowerShell version, Azure CLI, Az modules, and Azure authentication
.EXAMPLE
    .\Test-Prerequisites.ps1
.EXAMPLE
    .\Test-Prerequisites.ps1 -FixIssues
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$FixIssues
)

$ErrorActionPreference = "Stop"

# Color output functions
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Failure { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Header { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Yellow }

$issuesFound = 0
$issuesFixed = 0

Write-Header "Azure IP Migration Tool - Prerequisites Check"

# Check PowerShell Version
Write-Header "PowerShell Version"
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Write-Success "PowerShell $($psVersion.ToString()) (Required: 7.0+)"
}
else {
    Write-Failure "PowerShell $($psVersion.ToString()) (Required: 7.0+)"
    Write-Info "Download PowerShell 7: https://github.com/PowerShell/PowerShell/releases"
    Write-Info "Or run: winget install Microsoft.PowerShell"
    $issuesFound++
}

# Check Azure CLI
Write-Header "Azure CLI"
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    $azCliVersion = $azVersion.'azure-cli'
    $minVersion = [version]"2.60.0"
    $currentVersion = [version]$azCliVersion
    
    if ($currentVersion -ge $minVersion) {
        Write-Success "Azure CLI $azCliVersion (Required: 2.60+)"
    }
    else {
        Write-Failure "Azure CLI $azCliVersion is below minimum version 2.60.0"
        Write-Info "Update Azure CLI: az upgrade"
        Write-Info "Or download: https://docs.microsoft.com/cli/azure/install-azure-cli"
        $issuesFound++
    }
}
catch {
    Write-Failure "Azure CLI not found"
    Write-Info "Install Azure CLI:"
    Write-Info "  Windows: winget install Microsoft.AzureCLI"
    Write-Info "  Or download: https://docs.microsoft.com/cli/azure/install-azure-cli"
    $issuesFound++
    
    if ($FixIssues) {
        Write-Info "Attempting to install Azure CLI..."
        try {
            winget install Microsoft.AzureCLI --silent
            Write-Success "Azure CLI installation initiated"
            $issuesFixed++
        }
        catch {
            Write-Failure "Failed to install Azure CLI automatically"
        }
    }
}

# Check PowerShell Az Modules
Write-Header "PowerShell Az Modules"
$requiredModules = @('Az.Accounts', 'Az.Network', 'Az.Resources')
$missingModules = @()

foreach ($moduleName in $requiredModules) {
    $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
    
    if ($module) {
        Write-Success "$moduleName $($module.Version)"
    }
    else {
        Write-Failure "$moduleName not installed"
        $missingModules += $moduleName
        $issuesFound++
    }
}

if ($missingModules.Count -gt 0) {
    Write-Info "`nTo install missing modules, run:"
    Write-Host "  Install-Module -Name $($missingModules -join ', ') -Scope CurrentUser -Force" -ForegroundColor White
    
    if ($FixIssues) {
        Write-Info "`nAttempting to install missing modules..."
        foreach ($moduleName in $missingModules) {
            try {
                Write-Info "Installing $moduleName..."
                Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
                Write-Success "$moduleName installed successfully"
                $issuesFixed++
            }
            catch {
                Write-Failure "Failed to install $moduleName : $($_.Exception.Message)"
            }
        }
    }
}

# Check Azure Authentication (CLI)
Write-Header "Azure CLI Authentication"
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Success "Authenticated to Azure CLI"
        Write-Info "  Account: $($account.user.name)"
        Write-Info "  Subscription: $($account.name) ($($account.id))"
    }
}
catch {
    Write-Failure "Not authenticated to Azure CLI"
    Write-Info "Run: az login"
    $issuesFound++
}

# Check Azure Authentication (PowerShell)
Write-Header "Azure PowerShell Authentication"
try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($context) {
        Write-Success "Authenticated to Azure PowerShell"
        Write-Info "  Account: $($context.Account.Id)"
        Write-Info "  Subscription: $($context.Subscription.Name)"
    }
    else {
        Write-Failure "Not authenticated to Azure PowerShell"
        Write-Info "Run: Connect-AzAccount"
        $issuesFound++
    }
}
catch {
    Write-Failure "Not authenticated to Azure PowerShell"
    Write-Info "Run: Connect-AzAccount"
    $issuesFound++
}

# Check Configuration File
Write-Header "Configuration File"
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Config\migration-config.json"
if (Test-Path $configPath) {
    Write-Success "Configuration file exists"
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Info "  Subscription: $($config.subscriptionName)"
        Write-Info "  Subscription ID: $($config.subscriptionId)"
    }
    catch {
        Write-Failure "Configuration file is invalid JSON"
        $issuesFound++
    }
}
else {
    Write-Failure "Configuration file not found at: $configPath"
    $issuesFound++
}

# Check Permissions
Write-Header "Azure Permissions Check"
if ($context) {
    Write-Info "Checking role assignments (this may take a moment)..."
    try {
        $roles = Get-AzRoleAssignment -SignInName $context.Account.Id -ErrorAction SilentlyContinue
        $hasNetworkContributor = $roles | Where-Object { $_.RoleDefinitionName -in @('Network Contributor', 'Contributor', 'Owner') }
        
        if ($hasNetworkContributor) {
            Write-Success "Has required permissions (Network Contributor or higher)"
        }
        else {
            Write-Failure "Network Contributor role not found"
            Write-Info "Required: Network Contributor role on resource groups"
            $issuesFound++
        }
    }
    catch {
        Write-Info "Could not verify permissions (this is not critical)"
    }
}

# Summary
Write-Header "Summary"
if ($issuesFound -eq 0) {
    Write-Host "`n✓ All prerequisites met! You're ready to run the migration tool." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Review Config\migration-config.json" -ForegroundColor White
    Write-Host "  2. Run: .\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery" -ForegroundColor White
    exit 0
}
else {
    Write-Host "`n✗ Found $issuesFound issue(s)" -ForegroundColor Red
    
    if ($FixIssues -and $issuesFixed -gt 0) {
        Write-Host "✓ Fixed $issuesFixed issue(s)" -ForegroundColor Green
        Write-Host "`nPlease restart PowerShell and run this script again to verify." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nRun with -FixIssues flag to automatically fix some issues:" -ForegroundColor Yellow
        Write-Host "  .\Test-Prerequisites.ps1 -FixIssues" -ForegroundColor White
    }
    
    Write-Host "`nRefer to Docs\README.md for detailed setup instructions" -ForegroundColor Cyan
    exit 1
}
