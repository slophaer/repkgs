# Linux kernel for Golconda: monolithic server config, LLVM-built, no modules in round 1.
# Uses the kbuild build system with raw clang/lld from bootstrap.llvm on PATH (not jig).
{
  package,
  buildPkgs,
}:
let
  # Minimal server config that survives olddefconfig.
  # Options are verified after olddefconfig resolves dependencies.
  serverConfig = {
    # ===== Storage: virtio, nvme, ahci =====
    VIRTIO = "y";
    VIRTIO_PCI = "y";
    VIRTIO_BLK = "y";
    VIRTIO_NET = "y";
    VIRTIO_CONSOLE = "y";
    VIRTIO_BALLOON = "y";

    NVME_CORE = "y";
    BLK_DEV_NVME = "y";

    SATA_AHCI = "y";
    ATA = "y";
    BLK_DEV_SD = "y";
    SCSI = "y";

    BLK_DEV_LOOP = "y";

    # ===== EFI boot =====
    EFI = "y";
    EFI_STUB = "y";
    EFIVAR_FS = "y";

    # ===== Device mapper: verity, crypt, integrity =====
    BLK_DEV_DM = "y";
    DM_CRYPT = "y";
    DM_VERITY = "y";
    DM_INTEGRITY = "y";

    # ===== Filesystems =====
    EROFS_FS = "y";
    EROFS_FS_ZIP = "y";
    EROFS_FS_ZIP_ZSTD = "y";

    EXT4_FS = "y";
    EXT4_FS_POSIX_ACL = "y";
    EXT4_FS_SECURITY = "y";

    BTRFS_FS = "y";

    OVERLAY_FS = "y";

    VFAT_FS = "y";
    NLS_CODEPAGE_437 = "y";
    NLS_ISO8859_1 = "y";

    TMPFS = "y";
    TMPFS_POSIX_ACL = "y";

    FUSE_FS = "y";

    # ===== TPM =====
    TCG_TPM = "y";
    HW_RANDOM_TPM = "y";
    SECURITYFS = "y";

    # ===== systemd requirements =====
    CGROUPS = "y";
    MEMCG = "y";
    BLK_CGROUP = "y";
    CGROUP_SCHED = "y";

    BPF_SYSCALL = "y";

    SECCOMP = "y";

    FHANDLE = "y";
    DEVTMPFS = "y";
    DEVTMPFS_MOUNT = "y";

    NAMESPACES = "y";
    USER_NS = "y";
    NET_NS = "y";
    PID_NS = "y";
    UTS_NS = "y";
    IPC_NS = "y";

    INOTIFY_USER = "y";

    UNIX = "y";
    INET = "y";
    IPV6 = "y";

    # ===== Networking: netfilter, nftables =====
    NETFILTER = "y";
    NF_CONNTRACK = "y";
    NF_NAT = "y";
    NF_TABLES = "y";

    # ===== Virtual networking =====
    BRIDGE = "y";
    VLAN_8021Q = "y";
    MACVLAN = "y";
    VXLAN = "y";
    TUN = "y";

    # ===== Console and serial =====
    SERIAL_8250 = "y";
    SERIAL_8250_CONSOLE = "y";
    VT = "y";
    VT_CONSOLE = "y";
    TTY = "y";

    # ===== Framebuffer: minimal for EFI =====
    FB = "y";
    DRM = "y";
    FRAMEBUFFER_CONSOLE = "y";

    # ===== KVM guest support =====
    HYPERVISOR_GUEST = "y";
    PARAVIRT = "y";
    KVM_GUEST = "y";

    # ===== Crypto =====
    CRYPTO = "y";
    CRYPTO_AES = "y";
    CRYPTO_SHA256 = "y";
    CRYPTO_XTS = "y";

    # ===== No modules in round 1 =====
    MODULES = "n";




    # ===== Reproducibility: embedded config =====
    IKCONFIG = "y";
    IKCONFIG_PROC = "y";

    # ===== Debug: minimal =====
    DEBUG_KERNEL = "y";
    KALLSYMS = "y";
    PRINTK = "y";
    EARLY_PRINTK = "y";

    # ===== Unwinder: ORC (objtool/sorttable need pthreads; libunwind fixed in the glibc output) =====
    UNWINDER_ORC = "y";
    UNWINDER_FRAME_POINTER = "n";
  };
in
package {
  name = "linux-kernel";

  uses = [ "kbuild" ];

  kbuild.base = "defconfig";
  kbuild.config = serverConfig;
  # target auto-detected from platform in kbuild.nu
  kbuild.extraMake = [
    "LLVM=1"
    "LLVM_IAS=1"
    # Use raw clang/lld for kernel code (no jig hardening flags)
    "CC=clang"
    "LD=ld.lld"
    "AR=llvm-ar"
    "NM=llvm-nm"
    "STRIP=llvm-strip"
    "OBJCOPY=llvm-objcopy"
    "OBJDUMP=llvm-objdump"
    "READELF=llvm-readelf"
    # Use jig's cc for host tools: they need sysroot headers
    "HOSTCC=cc"
    "HOSTCXX=c++"
    "HOSTLD=ld.lld"
    "HOSTAR=llvm-ar"
    # Reproducibility
    "KBUILD_BUILD_TIMESTAMP=@315532800"
    "KBUILD_BUILD_USER=golconda"
    "KBUILD_BUILD_HOST=build"
    "KBUILD_BUILD_VERSION=1"
  ];

  # Disable jig's hardening: the kernel sets its own
  cc.hardening = false;

  # kconfig needs flex and bison; timeconst.h needs bc;
  # oid_registry needs perl
  buildDependencies = [
    buildPkgs.flex
    buildPkgs.bison
    buildPkgs.bc
    buildPkgs.perl
  ];

  # objtool needs elfutils headers/libs via pkg-config.
  # extract-cert needs openssl headers.
  # sorttable needs libunwind for pthread_exit at runtime.
  # These are safe: they only affect HOSTCC (jig) via -isystem,
  # which the kernel's own code ignores (it uses raw clang via CC=clang)
  dependencies = [
    buildPkgs.elfutils
    buildPkgs.openssl
    buildPkgs.libunwind
  ];

  # No version test: kernel has no --version flag
  bin = [ ];
  tests.run = false;

  platforms.os = [ "linux" ];
}
