# Notes on ravynOS PlatformExpert

### Device tree /defaults entries
```
    kern.maxvnodes
    kern.jetsam_delta
    kern.jetsam_critical_threshold
    kern.jetsam_idle_offset
    kern.jetsam_pressure_threshold
    kern.jetsam_freeze_threshold
    kern.jetsam_aging_policy
    kern.jetsam_idle_snapshot
    kern.io_throttle_window_tier1
    kern.io_throttle_window_tier2
    kern.io_throttle_window_tier3
    kern.io_throttle_period_tier1
    kern.io_throttle_period_tier2
    kern.io_throttle_period_tier3
    kern.maxkfsevents
    hw.memsize
    kern.disable_atm
    kern.atm_diagnostic_config
    kern.preferred_cpu_type
    kern.preferred_cpu_subtype
    kern.sched_pri_decay_limit
    kern.max_task_pmem
    kern.max_cpumon_percentage
    kern.max_cpumon_interval
    kern.vm_compressor
    kern.secluded_mem_mb
    progress-dy
```

### IOKit Registry properties

See `iokit/IOKit/IOKitKeys.h`

```
kDIRootImageResultKey
kDIRootImageDevTKey
kDIRootImageDevNameKey
kIOBSDNameKey
kIOBSDMajorKey
kIOBSDMinorKey
kIOPlatformUUIDKey
kIOReportLegendKey
kIOPMDeepSleepEnabledKey
kIOPMDestroyFVKeyOnStandbyKey
kIOHibernateMachineSignatureKey
kIOHibernatePreviewActiveKey
kIOScreenLockStateKey
kIOHibernateSMCVariablesKey
kIOPlatformMapperPresentKey
kIOPMRootDomainWakeTypeKey
kIOPMRootDomainWakeReasonKey
kIOHibernateOptionsKey
kRootDomainSupportedFeatures
kIOUserClientSharedInstanceKey
kIOUserClientMessageAppSuspendedKey
kIOUserClientCrossEndianCompatibleKey

"top-level"
"AAPL,ignore"
"AAPL,phandle"
"AAPL,slot-name"
"serial-number"
"unique-chip-id" 
"chip-id" 
"system-id" 
"platform-uuid" 
"apple-coprocessor-version"
"boot-device-path"
"boot-file-path"
"boot-ramdmg-size"
"boot-ramdmg-extents"
"boot-uuid" 
"acpi-device"
"no-idle"
"root-matching" 
"RAMDisk"
"reg" 
"interrupt-controller"
"interrupt-map"
"interrupt-map-mask" 
"interrupts"
"slot-names"
"dma-parent"
"iommu-id"
"Platform Memory Ranges"
"halt-restart-timeout" 
"IOPMStrictTreeOrder"
"IOPMUnattendedWakePowerState"
"IOPCITunnelled"
```