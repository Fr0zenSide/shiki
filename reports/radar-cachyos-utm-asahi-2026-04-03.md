# Radar: CachyOS + UTM + Asahi Linux -- Linux on Apple Silicon

**Date**: 2026-04-03
**Scope**: Linux distros for Apple Silicon, VM vs native, dev board strategy
**Status**: Research complete

---

## 1. CachyOS

### What Is It
Arch Linux-based distribution focused on performance optimization. Founded 2021, 114 public repos, active development. Ships custom kernels with advanced CPU schedulers (BORE, EEVDF, BMQ), LTO compilation, AutoFDO profiling, and gaming-oriented patches.

### Key Numbers
| Metric | Value |
|--------|-------|
| Stars (linux-cachyos) | 3,166 |
| Kernel patches repo | 298 stars |
| Public repos | 114 |
| Latest kernel | 6.17.9-cachyos (Dec 2025) |
| Fedora COPR | 220 stars |
| Handheld edition | 63 stars |
| Proton fork | 616 stars |

### ARM/aarch64 Support: NO
CachyOS is **x86-64 only**. All optimizations target x86-64, x86-64-v3, x86-64-v4, and znver4 (AMD Zen 4/5). Docker images are x86-64 and x86-64-v3 only. There is no aarch64 ISO, no ARM kernel config, and no ARM package repository.

The only ARM-adjacent work is a Raspberry Pi kernel fork (`linux-raspberrypi`, 6 stars) which is a mirror of the RPi Foundation kernel -- not a CachyOS ARM port.

### ShikkiOS Viability: NOT SUITABLE
CachyOS cannot be the base for ShikkiOS on ARM devices. Its entire value proposition (x86 micro-architecture optimizations, AVX2/AVX512 package rebuilds, x86 scheduler tuning) does not translate to ARM. However, CachyOS kernel patches (scheduler work, memory management, I/O improvements) could be cherry-picked for an ARM kernel build -- they are GPL-3.0 licensed.

### What Is Interesting
- **sched_ext support**: CachyOS ships with BPF-based extensible scheduler framework, allowing runtime scheduler swapping without reboot. Relevant for Shikki agent workloads.
- **Handheld edition**: Steam Deck-like experience with Gamescope session, `scx_lavd` latency-sensitive scheduler. Model for how a custom distro targets specific hardware.
- **Fedora COPR packages**: CachyOS kernels are available as Fedora packages. This means Fedora Asahi Remix could run CachyOS kernels if someone built aarch64 variants.
- **ananicy-rules** (160 stars): Per-process priority/scheduling rules. Useful pattern for agent workload management.

---

## 2. UTM

### What Is It
QEMU-based virtual machine manager for macOS and iOS. 33,506 stars, Apache 2.0 license, written in Swift. Supports 30+ processor architectures for emulation, plus Apple Hypervisor.framework for native ARM64 virtualization on macOS.

### Key Numbers
| Metric | Value |
|--------|-------|
| Stars | 33,506 |
| Latest release | v4.7.5 (Jan 2026) |
| QEMU backend | v10.0.2 |
| Open issues | 1,018 |
| Forks | 1,682 |

### iOS Distribution Variants
| Variant | JIT | Hypervisor | USB | How to Install |
|---------|-----|------------|-----|----------------|
| UTM.deb | Yes | Yes (M1+ iPad) | Yes | Jailbreak (Cydia) |
| UTM.ipa (sideload) | Yes (with workaround) | No | No | AltStore |
| UTM-HV.ipa | Yes | Yes (M1+ iPad) | Yes | TrollStore |
| UTM-SE.ipa (App Store) | **No** | No | No | App Store |
| UTM-Remote.ipa | N/A | N/A | No | Any |

### The JIT Problem (User Context Confirmed)
The App Store version (UTM SE) uses a **threaded interpreter** instead of JIT. This makes it 10-50x slower than JIT-enabled QEMU for CPU-intensive tasks. It is usable for light Linux CLI work but impractical for compiling code, running agents, or any real dev workload.

The TestFlight/sideloaded version with JIT requires workarounds (JitStreamer, AltStore JIT enablement) that are fragile and version-dependent. Apple actively patches JIT exploits.

### UTM Remote
UTM Remote is a **client app** that connects to a UTM host running on macOS. The VM runs on the Mac; the iPad/iPhone is just a display + input device. This means:
- Performance is that of the Mac, not the iPad
- Requires network connectivity to the Mac
- Currently iOS/iPadOS only (macOS Remote client requested but not shipped)
- Stability depends on network quality

### Can CachyOS Run in UTM on Apple Silicon?
**No, not natively.** CachyOS only provides x86-64 ISOs. UTM could emulate x86-64 to run CachyOS, but emulation performance would be terrible (no JIT on App Store, slow interpreter). On macOS with Hypervisor.framework, UTM can run ARM64 Linux VMs at near-native speed -- but CachyOS has no ARM64 build.

You could run **Arch Linux ARM** in UTM on macOS with hardware virtualization (fast), but that is vanilla Arch, not CachyOS.

### Can UTM Remote on iOS Run Linux Properly?
Yes, but the Linux VM runs on the **Mac**, not the iPad. The iPad is a thin client. This is actually a viable workflow if you have a Mac mini/Studio headless at home -- SSH + UTM Remote gives you a desktop Linux VM accessible from iPad. But it is not "Linux on iPad."

---

## 3. Asahi Linux

### What Is It
The project to bring Linux to Apple Silicon Macs natively. Led by Hector Martin (marcan) and Alyssa Rosenzweig (GPU driver). Founded Dec 2020. Reverse-engineered Apple's GPU, display controller, audio subsystem, and boot chain.

### Key Numbers
| Metric | Value |
|--------|-------|
| m1n1 bootloader | 4,038 stars |
| Kernel fork | 2,855 stars |
| Documentation | 2,146 stars |
| GPU research | 1,022 stars |
| muvm (microVM) | 842 stars |
| asahi-installer | 913 stars |
| speakersafetyd | 190 stars |
| asahi-audio | 203 stars |
| Orgs repos | 39 |

### Feature Support by Generation

#### M1 Series: DAILY-DRIVER READY
| Feature | Status |
|---------|--------|
| Boot/Install | Stable |
| GPU (OpenGL/Vulkan) | linux-asahi (Mesa upstream) |
| WiFi | Upstream (kernel 6.1) |
| Bluetooth | Upstream (kernel 6.2) |
| Speakers | linux-asahi (with speakersafetyd) |
| Microphones | linux-asahi |
| Webcam | linux-asahi |
| Keyboard/Trackpad | linux-asahi |
| NVMe | Upstream (kernel 5.19) |
| Suspend/Sleep | linux-asahi |
| USB2/USB3 | linux-asahi |
| Thunderbolt | WIP |
| DP Alt Mode | WIP |
| Video Decoder | WIP |
| TouchID | TBA |
| Neural Engine | Out of tree |

#### M2 Series: MOSTLY READY
Similar to M1 -- WiFi, BT, GPU, audio all working. Some device-specific features still landing.

#### M3 Series: EARLY/PARTIAL
- **No installer yet** for most M3 devices
- USB, NVMe, cpufreq work
- GPU: **TBA** (new GPU generation, needs driver work)
- DCP (display controller): **TBA**
- WiFi/BT: **TBA** for base M3 devices
- Keyboard/trackpad: Works on M3 Pro/Max MacBook Pro
- Speakers: **WIP**

#### M4 Series: NOT READY
- **No installer** for any M4 device
- Basic SoC blocks (USB, NVMe, cpufreq, RTC) work
- Everything else: **TBA**
- GPU, DCP, WiFi, BT, speakers, webcam -- all TBA

### GPU Drivers: The Crown Jewel
Alyssa Rosenzweig reverse-engineered Apple's AGX GPU and wrote a conformant OpenGL ES 3.1 and Vulkan 1.3 driver. The driver is now upstream in Mesa. This is arguably the most impressive reverse-engineering feat in recent Linux history. It provides hardware-accelerated 3D graphics on M1/M2 Macs running Linux.

For M3/M4, the GPU architecture changed (new ISA revision) and driver work has not started yet.

### Audio: Solved Problem (M1/M2)
- **speakersafetyd**: Rust daemon that protects laptop speakers from damage (first FOSS smart amp implementation)
- **asahi-audio**: PipeWire/WirePlumber DSP profiles for each Mac model
- Speakers, microphones, headphone jacks, HDMI audio all working on M1/M2
- Goal stated as "better than macOS" audio quality

### The 16K Page Size Issue
Apple Silicon uses 16K pages. Most x86-centric Linux software assumes 4K pages. This causes segfaults in software with hardcoded page alignments. Asahi's solution:
- **muvm** (842 stars): Run 4K-page-dependent software in a microVM using libkrun. Supports GPU passthrough, Wayland forwarding, and FEX-Emu for x86 translation. This is how you run things like Electron apps that assume 4K pages.
- Long-term: upstream fixes to software (Emacs, Chromium, etc. already fixed)

### Widevine/DRM
Working via a custom installer. Netflix, Spotify, etc. work in Firefox and Chromium on Asahi.

### Fedora Asahi Remix: The Recommended Distro
The official recommended distro is Fedora Asahi Remix (based on Fedora, maintained by the Asahi team). It is the most polished experience with pre-configured audio, GPU drivers, and hardware support. For M1/M2 Macs it is genuinely daily-driver ready for development work.

---

## Key Questions Answered

### 1. Best Path to Linux on iPad: UTM (VM) vs Asahi (native) vs Waiting for Apple?

**None of these work for iPad today.** Here is why:

| Path | iPad Status | Verdict |
|------|------------|---------|
| UTM (App Store) | Works but no JIT = unusable perf | Dead end for dev work |
| UTM (sideload) | JIT workarounds fragile, Apple patches them | Unreliable |
| UTM Remote | iPad is thin client, VM runs on Mac | Best current option but requires a Mac |
| Asahi Native | iPad not supported at all (Mac-only installer) | Not applicable |
| Apple official | No sign Apple will ever allow this | Do not hold breath |

**Recommendation**: For "Linux on iPad" the practical answer today is **UTM Remote to a Mac mini running a Linux VM**, or **SSH to a headless Linux box** (real or cloud). For native ARM Linux dev, use an **M1/M2 Mac running Fedora Asahi Remix** as a dual-boot or dedicated machine.

The dream of native Linux on iPad requires either:
1. Asahi reverse-engineering the iPad boot chain (extremely unlikely -- different secure boot model, no iBoot exploit path)
2. Apple opening up iPadOS (not happening)
3. A jailbreak + custom bootloader (no modern jailbreaks exist for M-series iPads)

### 2. Can Shikki Run on Any of These?

| Platform | Swift Available | Shikki Viable | Notes |
|----------|----------------|---------------|-------|
| Fedora Asahi Remix (M1/M2 Mac) | Yes (swift.org ARM64 Linux) | **YES** | Best option. Native ARM64 Linux with GPU. |
| UTM ARM64 VM on macOS | Yes | Yes | Near-native perf with Hypervisor.framework |
| UTM on iPad (App Store) | Interpreter only | No | Too slow |
| UTM Remote (iPad -> Mac) | N/A (runs on Mac) | Yes (on Mac side) | iPad is just display |
| CachyOS | x86 only | No | No ARM64 support |

**Fedora Asahi Remix on an M1/M2 Mac is the only viable path for running Shikki natively on Linux today.** Swift toolchain is available for aarch64 Linux. ShikkiKit would need to be tested against the Linux Swift runtime but there are no fundamental blockers.

### 3. ARM Linux Distro Recommendation for Shikki Dev Boards

For Tegami (custom dev boards) and Pi-like devices:

| Distro | Recommendation | Why |
|--------|---------------|-----|
| **Fedora (aarch64)** | **TOP PICK** | Best ARM64 support, largest package set, systemd, Swift available. Asahi team chose it for a reason. |
| **Ubuntu Server (ARM64)** | Runner-up | Canonical maintains ARM64 well. More enterprise support. |
| **Arch Linux ARM** | Power users | Rolling release, bleeding edge, but less stable. No CachyOS optimizations. |
| **Alpine Linux (aarch64)** | Embedded/minimal | Musl-based, tiny footprint. Good for constrained boards. |
| **Debian (aarch64)** | Stability-first | Slower package updates but rock-solid. |

**Pick Fedora aarch64** for Tegami boards. It aligns with Fedora Asahi Remix (shared package base), has excellent ARM64 support, and Swift packages are available. CachyOS kernel patches (sched_ext, BORE scheduler) could be applied to a custom Fedora kernel build for performance tuning.

---

## Action Items for Shikki

### Adopt (do now)
- [ ] **Test Shikki on Fedora Asahi Remix**: Set up an M1 Mac mini as a Linux dev/CI node. Validate Swift toolchain + ShikkiKit compilation on aarch64 Linux.
- [ ] **Fedora aarch64 for Tegami board spec**: When specifying Tegami hardware, target Fedora aarch64 as the reference OS.

### Trial (experiment)
- [ ] **muvm for 4K-page compat**: If Shikki agents call x86 tools (Node.js older versions, Electron-based tools), muvm provides transparent compatibility. Worth a spike.
- [ ] **CachyOS sched_ext patches on Fedora**: The BPF extensible scheduler could optimize agent workload scheduling. Build a custom kernel with sched_ext for the CI node.

### Assess (watch)
- [ ] **Asahi M3/M4 progress**: GPU and display drivers for M3/M4 are TBA. Check quarterly. No action until installer ships.
- [ ] **UTM Remote stability**: Monitor for macOS Remote client. If shipped, it could enable iPad as a first-class thin client for Shikki dev.
- [ ] **muvm GPU passthrough maturity**: Currently supports asahi/amdgpu/freedreno. If it stabilizes, it solves the 16K page problem cleanly.

### Hold (not actionable)
- [ ] **Linux on iPad**: No viable path exists today. Revisit only if Asahi announces iPad support or Apple opens iPadOS.
- [ ] **CachyOS as ShikkiOS base**: x86-only. Would need a full ARM64 port to be useful. Not worth the effort when Fedora aarch64 exists.

---

## Architecture Notes

### muvm -- Worth Watching
Asahi's `muvm` (842 stars) is a lightweight VM runner using libkrun that mounts the host filesystem, forwards Wayland, and passes through GPU. It solves the 4K/16K page mismatch transparently. This pattern -- "run legacy binaries in a micro-VM with host integration" -- is relevant for Shikki's agent execution model where agents might invoke tools with different runtime requirements.

### speakersafetyd -- Engineering Excellence
The Rust-based speaker safety daemon models Thiele/Small parameters in real-time to prevent speaker damage. First FOSS implementation of a smart amp. Demonstrates the Asahi team's depth -- they do not just port Linux, they solve hardware problems Apple solved in proprietary firmware. This is the caliber of engineering Shikki should aspire to for hardware integration.

### sched_ext -- Future of Linux Scheduling
CachyOS and Meta co-develop sched_ext, allowing BPF programs to define CPU scheduling policy at runtime. Schedulers like `scx_lavd` (latency-aware for gaming) and `scx_rusty` (load balancing) can be swapped without reboot. For Shikki agent orchestration on Linux, writing a custom sched_ext scheduler that prioritizes agent workloads is a real possibility.

---

## Summary

| Project | Stars | ARM64 | Daily-Driver | Shikki Path |
|---------|-------|-------|-------------|-------------|
| CachyOS | 3.2k | No | Yes (x86) | Kernel patches only |
| UTM | 33.5k | Host only | macOS yes, iOS limited | VM host, not target |
| Asahi Linux | 4k+ (m1n1) | Yes (Apple Silicon) | M1/M2 yes, M3/M4 no | Primary Linux target |

**Bottom line**: Fedora Asahi Remix on M1/M2 Mac hardware is the only production-viable path for Shikki on native ARM64 Linux today. CachyOS contributes valuable kernel technology but not an ARM distro. UTM is a useful dev tool on macOS but not a deployment target.
