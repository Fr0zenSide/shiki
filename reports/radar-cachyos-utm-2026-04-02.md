# Radar: CachyOS + UTM -- Linux Dev Environment on Apple Silicon & iPad

**Date**: 2026-04-02
**Category**: Infrastructure / ShikkiOS exploration
**Status**: WATCH (no action yet)

---

## 1. CachyOS

### What is it?
CachyOS is an Arch Linux-based distribution focused on **performance optimization**. Founded June 2021, it ships custom kernels with advanced CPU schedulers, compiler optimizations (LTO, PGO, AutoFDO, BOLT), and tuned system settings out of the box.

- **GitHub org**: [github.com/CachyOS](https://github.com/CachyOS) -- 114 public repos, 3.5k followers
- **Main repo**: `linux-cachyos` -- 3,165 stars, 104 forks, GPL-3.0
- **Website**: [cachyos.org](https://cachyos.org)
- **Community**: Discord (linked from repo), active development (daily commits as of 2026-04-02)

### Key Packages & Optimizations

| Area | Details |
|------|---------|
| **Kernel schedulers** | BORE (gaming/interactive), EEVDF (general), BMQ (bitmap queue) |
| **Compiler** | GCC + Thin LTO default, Clang + AutoFDO + Propeller variant |
| **Architecture tiers** | x86-64, x86-64-v3 (AVX2), x86-64-v4 (AVX-512), znver4 (Zen 4/5) |
| **Specialized kernels** | `-hardened` (security), `-lts` (stability), `-rt-bore` (realtime), `-server`, `-deckify` (Steam Deck) |
| **System tuning** | ZRAM (zstd), I/O scheduler auto-assignment (BFQ/mq-deadline/none), sysctl tweaks, THP optimization |
| **Hardware** | Steam Deck, ROG Ally, Lenovo Legion handhelds, T2 MacBooks, NVIDIA (proprietary + open) |
| **Filesystem** | ZFS built-in, btrfs default, bcachefs experimental, xfs, ext4 |
| **Handheld edition** | `CachyOS-Handheld` -- scx_lavd scheduler, Gamescope session, HDR, full gaming stack |
| **Browser** | Custom Cachy Browser (archived, based on Firefox) |
| **Hardware detection** | `chwd` -- Rust-based hardware detection and configuration |
| **CLI installer** | C++ installer with filesystem/bootloader choices |

### ARM / aarch64 Support

**Verdict: NO native aarch64 support.**

- All CachyOS repository tiers are x86-64 only: `x86-64`, `x86-64-v3`, `x86-64-v4`, `znver4`
- The installation requirements page explicitly lists x86-64 microarchitecture levels only
- Their optimized package repos are compiled for x86-64 instruction sets (AVX2, AVX-512, etc.)
- The `linux-raspberrypi` repo exists (6 stars) but is just a mirror of the upstream Raspberry Pi kernel tree -- it is NOT a CachyOS-for-ARM effort
- There are 26 `aarch64` references in PKGBUILDs, but these are standard Arch `arch=()` array entries, not active ARM builds
- The Handheld edition targets x86-64 handhelds (Steam Deck, ROG Ally, Legion Go) -- all AMD APUs

**Bottom line**: CachyOS is fundamentally an x86-64 performance distro. Their value proposition (x86-64-v3/v4 compiler optimizations, AVX-512, znver4 tuning) has no equivalent on ARM. Running CachyOS on aarch64 is not possible today and is not on their roadmap.

---

## 2. UTM

### What is it?
UTM is a **QEMU-based virtual machine manager** for macOS and iOS, written in Swift. It supports both hardware-accelerated virtualization (Hypervisor.framework on macOS) and full system emulation (QEMU TCG).

- **GitHub org**: [github.com/utmapp](https://github.com/utmapp) -- 40 public repos, 1.9k followers
- **Main repo**: `UTM` -- **33,505 stars**, 1,682 forks, Apache-2.0
- **Website**: [getutm.app](https://getutm.app)
- **Latest release**: v4.7.5 (2026-01-03) -- QEMU v10.0.2 backend, Liquid Glass UI, App Intents automation

### Capabilities

| Feature | macOS | iOS (full) | iOS (SE) | iOS (Remote) |
|---------|-------|-----------|----------|-------------|
| Hardware virtualization | Yes (Hypervisor.framework) | M1 iPad+ (TrollStore) | No | N/A (thin client) |
| JIT acceleration | Yes | Jailbreak/TrollStore | No (threaded interpreter) | N/A |
| ARM64 guests | Yes (native speed) | Yes | Yes | Via macOS server |
| x86-64 guests | Yes (emulated) | Yes (emulated) | Yes (slow) | Via macOS server |
| USB passthrough | Yes | Jailbreak/TrollStore | No | No |
| 30+ CPU architectures | Yes | Yes | ARM/PPC/RISC-V/x86 only | Via macOS server |

### UTM Remote

UTM Remote is a **dedicated thin client app** for iOS/iPadOS that connects to UTM Server running on macOS.

- **App Store**: Free ([UTM Remote - Virtual Machines](https://apps.apple.com/us/app/utm-remote-virtual-machines/id6470773592))
- **TestFlight**: Beta available
- **Server requirement**: UTM for macOS v4.5.2+ with "Server" mode enabled
- **Only QEMU-backend VMs** are supported (not Apple Virtualization VMs)
- **Discovery**: Bonjour (LAN auto-discover) or manual IP/hostname entry
- **Security**: Fingerprint-based pairing + optional password
- **External access**: UPnP/NAT-PMP auto-config or manual port forwarding
- **Interface**: Mirrors full UTM -- start/stop/interact with VMs from iPad/iPhone

### Pre-built VM Templates

UTM provides downloadable VM images including **Arch Linux ARM64** (built from archlinuxarm.org). This is plain Arch Linux ARM, not CachyOS.

---

## 3. Direct Answers

### Q1: Can CachyOS run on ARM (aarch64)?

**No.** CachyOS is x86-64 only. All kernels, optimized packages, and repository infrastructure target x86-64 microarchitecture levels. There is no ARM build, no ARM ISO, and no indication of ARM support on their roadmap. The performance optimizations that define CachyOS (AVX2/AVX-512 builds, znver4 tuning) are inherently x86 features.

### Q2: Can UTM run CachyOS on macOS (Apple Silicon)?

**Technically yes, but poorly.** UTM can emulate x86-64 on Apple Silicon via QEMU TCG. You could boot a CachyOS x86-64 ISO in an emulated x86-64 VM. However:
- Performance would be terrible (full x86-64 emulation, no hardware acceleration)
- All of CachyOS's x86-64-v3/v4 optimizations would be wasted under emulation
- You would get better results running plain Arch Linux ARM64 with hardware virtualization (near-native speed via Hypervisor.framework)

**Verdict**: Possible but counterproductive. Use Arch Linux ARM64 instead.

### Q3: Can UTM Remote run CachyOS on iOS/iPadOS?

**Yes, indirectly.** UTM Remote is a thin client that connects to UTM Server on macOS. If you set up a CachyOS x86-64 VM on your Mac (emulated), you could access it from iPad via UTM Remote. But:
- The VM runs on macOS, not on iPad
- Same emulation performance penalty applies
- Network latency adds to the poor experience
- An Arch Linux ARM64 VM with hardware virtualization on the Mac, accessed via UTM Remote, would be dramatically faster

### Q4: Would this give us a full shid environment on iPad?

**Not via CachyOS, but yes via Arch Linux ARM64 + UTM Remote.** The viable path:

1. Run **Arch Linux ARM64** VM on Mac mini/MacBook with UTM (hardware-accelerated, near-native speed)
2. Install shid toolchain inside the ARM64 VM (Swift, NATS, PocketBase, etc.)
3. Connect from iPad via **UTM Remote** over LAN or VPN
4. Full Linux terminal + GUI available on iPad as a thin client

This gives you a real Linux dev environment accessible from iPad without CachyOS. CachyOS adds nothing here -- its value is x86-64 performance tuning, which is irrelevant when running ARM64 VMs.

---

## 4. ShikkiOS Relevance Assessment

### CachyOS as ShikkiOS base

| Criterion | Assessment |
|-----------|-----------|
| ARM support | Not available -- dealbreaker for dev boards / ARM servers |
| Kernel quality | Excellent for x86-64 desktop/gaming |
| System tuning | Great patterns to study (sysctl, I/O scheduler, ZRAM) |
| Installer | C++ CLI installer -- good reference for `shikki setup` |
| Hardware detection | `chwd` (Rust) -- interesting pattern for device profiles |
| Server variant | Exists (`-server` kernel) but x86-64 only |
| Community | Active but desktop/gaming focused, not server/embedded |

**Verdict**: CachyOS is NOT suitable as a ShikkiOS base for ARM targets. However, their system tuning patterns (sysctl, I/O scheduler assignment, ZRAM config, THP management) are worth studying for any custom Linux setup.

### What to use instead for ShikkiOS on ARM

For ARM-based dev boards and servers, consider:
- **Arch Linux ARM** (archlinuxarm.org) -- same Arch base, native ARM64
- **Alpine Linux** -- minimal, musl-based, excellent for containers/servers on ARM
- **NixOS** -- declarative, reproducible, good ARM64 support
- **Fedora Server** -- strong ARM64 support, SELinux, systemd-first

### UTM as iPad dev environment

| Criterion | Assessment |
|-----------|-----------|
| Maturity | Very mature (33k stars, v4.7.5, active development) |
| Remote access | UTM Remote works well over LAN |
| Performance | Near-native for ARM64 guests on Apple Silicon |
| Automation | App Intents in v4.7+ for Shortcuts integration |
| Stability | Solid -- regular releases, responsive maintainer |

**Verdict**: UTM + UTM Remote is a viable path for iPad-based Linux dev, but requires a Mac as the VM host. For a true portable setup, a Mac mini as always-on server + iPad as thin client is the play.

---

## 5. Action Items

| Priority | Action | Status |
|----------|--------|--------|
| WATCH | Monitor CachyOS for any ARM64 announcements | No action needed |
| STUDY | Extract CachyOS sysctl/ZRAM/I/O tuning patterns for future server configs | When relevant |
| WATCH | Track UTM Remote improvements (external access, visionOS) | No action needed |
| PARK | iPad dev environment via UTM Remote -- requires Mac mini server investment | Future consideration |

---

## 6. Key Takeaways

1. **CachyOS is x86-64 only** -- impressive performance distro but irrelevant for ARM/ShikkiOS
2. **UTM Remote is production-ready** -- real thin client for iOS/iPadOS to macOS VMs
3. **The iPad dev path is Arch ARM64 + UTM, not CachyOS** -- hardware virtualization beats x86 emulation
4. **CachyOS tuning patterns are worth stealing** -- their sysctl, scheduler, and ZRAM configs are battle-tested
5. **For ShikkiOS on ARM**, look at Arch Linux ARM, Alpine, or NixOS instead
