# Azure Public IP Migration - Implementation TODO

## Current Status
✅ Project structure created
✅ Configuration file created
✅ Common functions module completed
✅ Main migration script framework created
✅ Validation and rollback script frameworks created
✅ Documentation structure established

## Immediate Tasks (Week 1)

### High Priority
1. [ ] Test Discovery phase in production subscription
   - Run: `.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery`
   - Verify all Basic IPs are found
   - Review inventory CSV output

2. [ ] Review and update configuration
   - Update subscription ID if needed
   - Configure batch size and soak period
   - Set DNS zone information

3. [ ] Test Create phase with 1-2 test IPs
   - Use dry run mode first
   - Verify Standard IP creation
   - Check secondary IP config on NICs

4. [ ] Complete full implementation of migration phases
   - Expand Create phase logic (currently stub)
   - Expand Validate phase logic (currently stub)
   - Expand Cleanup phase logic (currently stub)

5. [ ] Initialize Git repository and push to GitHub
   - See section below for Git setup

### Medium Priority
6. [ ] Add retry logic for API failures
7. [ ] Implement progress indicators
8. [ ] Add NSG rule detailed validation
9. [ ] Create HTML report generation
10. [ ] Document special cases (LB, VPN Gateway)

## Git Repository Setup

### Initialize Local Repository
```bash
cd D:\dev2\basic-to-standard-ip-azure
git init
git add .
git commit -m "Initial commit: Azure Basic to Standard IP migration tool"
```

### Create GitHub Repository
```bash
# Using GitHub CLI (gh)
gh repo create basic-to-standard-ip-azure --public --source=. --remote=origin --push

# OR manually:
# 1. Go to https://github.com/new
# 2. Repository name: basic-to-standard-ip-azure
# 3. Description: "Automated PowerShell tool for migrating Azure Basic SKU Public IPs to Standard SKU with zero downtime"
# 4. Public repository
# 5. Do NOT initialize with README (we have one)
# 6. Create repository
# 7. Follow instructions to push existing repository
```

### Push to GitHub
```bash
git remote add origin https://github.com/YOUR_USERNAME/basic-to-standard-ip-azure.git
git branch -M main
git push -u origin main
```

## Migration Execution Plan

### Week 1: Testing and Validation
- [ ] Complete implementation of all phases
- [ ] Test discovery in dev/test subscription
- [ ] Dry run on 2-3 test IPs
- [ ] Validate rollback capability
- [ ] Document any issues found

### Week 2: East US Migration
- [ ] Lower DNS TTL for East US IPs (48h before)
- [ ] Run Discovery phase
- [ ] Run Create phase (5 IPs batch)
- [ ] Run Validate phase
- [ ] Update DNS records
- [ ] Monitor for 48-hour soak period

### Week 3: East US Cleanup + West US Start
- [ ] Run Cleanup for East US
- [ ] Verify East US migration complete
- [ ] Start West US batch 1 (5 IPs)

### Week 4-5: Complete All Regions
- [ ] West US batch 2
- [ ] West US 2 (2 IPs)
- [ ] West US 3 (1 IP)

### Week 6: Final Validation
- [ ] Verify all migrations complete
- [ ] Delete any remaining Basic IPs
- [ ] Document lessons learned

## Known Issues and Limitations

### Issue #1: Stub Implementations
**Status**: In Progress
**Description**: Main migration phases (Create, Validate, Cleanup) are currently stubs
**Action Required**: Complete full implementations
**Priority**: Critical

### Issue #2: Load Balancer Migration Not Automated
**Status**: By Design
**Description**: Basic LB upgrades require manual process per Microsoft guidance
**Workaround**: Follow Microsoft LB upgrade documentation
**Priority**: Medium

### Issue #3: VPN Gateway Migration Not Automated
**Status**: By Design
**Description**: VPN Gateway migrations require manual process
**Workaround**: Follow Microsoft VPN Gateway migration documentation
**Priority**: Medium

## File Structure Status

```
✅ basic-to-standard-ip-azure/
├── ✅ Config/
│   └── ✅ migration-config.json
├── ✅ Scripts/
│   ├── ✅ Common-Functions.ps1 (COMPLETE)
│   ├── ⚠️ Migrate-BasicToStandardIP.ps1 (NEEDS EXPANSION)
│   ├── ⚠️ Validate-Migration.ps1 (NEEDS EXPANSION)
│   └── ⚠️ Rollback-Migration.ps1 (NEEDS EXPANSION)
├── ✅ Docs/
│   ├── ✅ REQUIREMENTS.md
│   ├── ✅ TODO.md (this file)
│   ├── ⏳ FUTURE.md (in progress)
│   └── ⏳ Full README.md (in progress)
├── ✅ Logs/
├── ✅ Output/
├── ✅ .gitignore
└── ✅ README.md (short version)
```

Legend:
- ✅ Complete
- ⚠️ Partial/Needs Work
- ⏳ In Progress
- ❌ Not Started

## Next Actions (Priority Order)

1. **Complete implementation stubs** - Expand Create, Validate, Cleanup phases
2. **Test Discovery phase** - Verify it works in target subscription
3. **Initialize Git repository** - Push to GitHub
4. **Run dry run tests** - Test with 1-2 IPs in non-production
5. **Begin production migration** - Start with East US

## Notes
- Always use dry run mode for initial testing
- Keep inventory CSV files for audit trail
- Monitor logs after each phase
- Have rollback plan ready
- Document any deviations from plan
