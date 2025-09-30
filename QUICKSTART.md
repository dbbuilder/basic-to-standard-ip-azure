# Quick Start Guide - Azure IP Migration Tool v2.0

## ✅ Your Tool is Ready!

**Status**: Fully tested and working  
**Version**: 2.0 with Multi-Subscription Support  
**Last Test**: September 29, 2025 - Successfully discovered 11 Basic IPs

---

## 🚀 Quick Commands

### 1. Check Prerequisites
```powershell
cd D:\dev2\basic-to-standard-ip-azure\Scripts
.\Test-Prerequisites.ps1
```
✅ **Result**: All prerequisites met!

### 2. Discover IPs
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery
```
✅ **Result**: Found 11 Basic IPs (9 unattached, 2 VM-attached)

### 3. Test Create Phase (DryRun)
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun
```

### 4. Create Standard IPs
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create
```

### 5. Validate
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate
```

### 6. Cleanup (after 48 hours)
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

---

## 📊 Your Current IPs

### Unattached (9) - Ready for Pilot ✅
1. DataCentral-ip (West US)
2. DataEastern-ip (West US)
3. dataMountain-ip (West US)
4. DataPacific-ip (West US)
5. AppArizona-ip (East US)
6. AppCentral-ip (East US)
7. AppEastern-ip (East US)
8. AppMountain-ip (East US)
9. AppPacific-ip (East US)

### VM-Attached (2) - Requires DNS Coordination ⚠️
10. Windermere-vm-ip (West US 2) → windermere-vm352
11. SunCityWest-VM-ip (West US 3) → suncitywest-vm245

---

## 🎯 Recommended First Steps

### This Week: Pilot with Unattached IPs

**Step 1**: Test with DryRun
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun
```

**Step 2**: Execute Create
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create
```

**Step 3**: Validate
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate
```

**Step 4**: Wait 24 hours, then Cleanup
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

---

## 📁 Important Files

### Latest Inventory
```powershell
# View latest inventory
$csv = Get-ChildItem ..\Output\inventory_*.csv | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Import-Csv $csv.FullName | Format-Table Name, Location, IpAddress, ConsumerType
```

### Latest Log
```powershell
# View latest log
$log = Get-ChildItem ..\Logs\migration_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $log.FullName -Tail 50
```

---

## ⚙️ Configuration

### Current Settings
**File**: `Config\migration-config.json`

**Key Settings**:
- `scanAllSubscriptions`: true (scans all subscriptions)
- `soakPeriodHours`: 48 (wait time before cleanup)
- `batchSize`: 5 (IPs processed per batch)

### Enable/Disable Multi-Subscription
```json
{
  "scanAllSubscriptions": false,  // Single subscription
  "scanAllSubscriptions": true    // All subscriptions
}
```

---

## 🔧 Troubleshooting

### Issue: Modules Not Found
**Solution**: The modules ARE installed. Run:
```powershell
.\Test-Prerequisites.ps1
```

### Issue: Not Authenticated
**Solution**: Re-authenticate
```powershell
Connect-AzAccount
az login
```

### Issue: Subscription Not Set
**Solution**: Set correct subscription
```powershell
Set-AzContext -SubscriptionId "7ad813f6-5b95-449a-b341-e1c1854d9d67"
az account set --subscription "7ad813f6-5b95-449a-b341-e1c1854d9d67"
```

---

## 📖 Documentation

1. **MULTI-SUBSCRIPTION-UPDATE.md** - Latest features (v2.0)
2. **SUCCESS-REPORT.md** - Test results and recommendations
3. **Docs/MULTI-SUBSCRIPTION.md** - Complete multi-sub guide
4. **Docs/README.md** - Full user manual

---

## ⚠️ Important Notes

### DryRun is Your Friend
**Always** test with `-DryRun` first!
```powershell
-DryRun  # Shows what will happen, makes NO changes
```

### Zero Downtime Strategy
1. Standard IP created as **secondary** on NIC
2. Both IPs active during DNS cutover
3. No connection resets
4. Basic IP removed after soak period

### Soak Period
- **Default**: 48 hours
- **Purpose**: Ensure Standard IP is stable
- **Required**: Before cleanup phase

---

## 🎉 Success Indicators

### ✅ Discovery Successful
```
Total Basic Public IPs: 11
By Consumer Type:
  nic: 2
  unattached: 9
```

### ✅ Create Successful
```
SUCCESS: Standard IP created at x.x.x.x
```

### ✅ Validate Successful
```
VALIDATION PASSED
```

### ✅ Cleanup Successful
```
Basic IP removed successfully
```

---

## 🚀 Next Action

**Start Here**:
```powershell
cd D:\dev2\basic-to-standard-ip-azure\Scripts

# Test with DryRun
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# Review what it would do, then execute for real
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create
```

---

## 📞 Need Help?

1. Check logs in `Logs\` directory
2. Review `SUCCESS-REPORT.md`
3. Read `Docs/README.md`
4. Check GitHub: https://github.com/dbbuilder/basic-to-standard-ip-azure

---

**Repository**: https://github.com/dbbuilder/basic-to-standard-ip-azure  
**Version**: 2.0  
**Status**: ✅ Production Ready  
**Tested**: September 29, 2025

**You're ready to migrate! Start with the 9 unattached IPs for a low-risk pilot.**

---

*Quick Start Guide - Azure IP Migration Tool v2.0*  
*Last Updated: September 29, 2025*
