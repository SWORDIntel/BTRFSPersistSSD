#!/usr/bin/env python3
"""
MMDEBSTRAP PYTHON ORCHESTRATOR INTEGRATION
Advanced mmdebstrap bootstrap with Python orchestrator capabilities

Features:
- 2-3x faster bootstrap compared to debootstrap
- Automatic security updates inclusion
- Multiple mirror support for reliability
- Comprehensive error handling and logging
- Build profile management
- Orchestrator module integration
- Automatic fallback to debootstrap

Version: 3.0.0
Author: Build Orchestrator Team
"""

import os
import sys
import json
import logging
import argparse
import subprocess
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Union, Tuple
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, asdict

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class BootstrapMethod(Enum):
    """Available bootstrap methods"""
    MMDEBSTRAP = "mmdebstrap"
    DEBOOTSTRAP = "debootstrap"
    AUTO = "auto"

class BuildProfile(Enum):
    """Available build profiles"""
    MINIMAL = "minimal"
    STANDARD = "standard" 
    DEVELOPMENT = "development"
    ZFS_OPTIMIZED = "zfs_optimized"
    SECURITY = "security"

@dataclass
class BootstrapConfig:
    """Configuration for mmdebstrap bootstrap process"""
    suite: str = "noble"
    architecture: str = "amd64"
    build_profile: BuildProfile = BuildProfile.STANDARD
    enable_zfs: bool = False
    enable_security: bool = False
    project_root: Path = Path.cwd()
    cache_dir: Optional[Path] = None
    
    def __post_init__(self):
        if self.cache_dir is None:
            self.cache_dir = self.project_root / "cache" / "mmdebstrap"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

class MmdebstrapOrchestrator:
    """Main orchestrator class for mmdebstrap bootstrap integration"""
    
    # Package profiles for different build types
    PACKAGE_PROFILES = {
        BuildProfile.MINIMAL: [
            "systemd", "dbus", "apt-utils", "locales"
        ],
        BuildProfile.STANDARD: [
            "systemd", "dbus", "apt-utils", "locales", "sudo",
            "wget", "curl", "gnupg", "ca-certificates", "openssh-server",
            "nano", "vim-tiny"
        ],
        BuildProfile.DEVELOPMENT: [
            "systemd", "dbus", "apt-utils", "locales", "sudo",
            "build-essential", "git", "python3", "python3-pip",
            "nodejs", "npm", "docker.io"
        ],
        BuildProfile.ZFS_OPTIMIZED: [
            "systemd", "dbus", "apt-utils", "locales", "sudo",
            "zfsutils-linux", "zfs-dkms", "linux-headers-generic",
            "smartmontools", "hdparm"
        ],
        BuildProfile.SECURITY: [
            "systemd", "dbus", "apt-utils", "locales", "sudo",
            "cryptsetup", "gnupg2", "openssl", "fail2ban",
            "ufw", "apparmor", "auditd"
        ]
    }
    
    def __init__(self, config: BootstrapConfig):
        self.config = config
        self.logger = logging.getLogger(f"{__name__}.{self.__class__.__name__}")
        self.bootstrap_method = self._detect_bootstrap_method()
        
        # Setup mirrors
        self.mirrors = [
            "http://archive.ubuntu.com/ubuntu",
            "http://security.ubuntu.com/ubuntu"
        ]
        
    def _detect_bootstrap_method(self) -> BootstrapMethod:
        """Auto-detect best available bootstrap method"""
        if shutil.which("mmdebstrap"):
            self.logger.info("✓ mmdebstrap detected - using advanced bootstrap")
            return BootstrapMethod.MMDEBSTRAP
        elif shutil.which("debootstrap"):
            self.logger.warning("mmdebstrap not found - falling back to debootstrap")
            return BootstrapMethod.DEBOOTSTRAP
        else:
            raise RuntimeError("No bootstrap tool found - install mmdebstrap or debootstrap")
    
    def execute_bootstrap(self, chroot_dir: Union[str, Path]) -> bool:
        """Execute bootstrap with full orchestrator integration"""
        self.logger.info("Starting mmdebstrap orchestrator bootstrap")
        self.logger.info(f"Target: {chroot_dir}")
        self.logger.info(f"Configuration: {self.config.suite}/{self.config.architecture}/{self.config.build_profile.value}")
        
        chroot_path = Path(chroot_dir)
        
        try:
            # Pre-bootstrap setup
            self._setup_bootstrap_environment(chroot_path)
            
            # Execute bootstrap based on detected method
            if self.bootstrap_method == BootstrapMethod.MMDEBSTRAP:
                success = self._execute_mmdebstrap(chroot_path)
            else:
                success = self._execute_debootstrap_fallback(chroot_path)
            
            if success:
                # Post-bootstrap integration
                self._integrate_orchestrator_modules(chroot_path)
                self._create_bootstrap_metadata(chroot_path)
                self._verify_bootstrap_result(chroot_path)
                
                self.logger.info("✓ Bootstrap completed successfully")
                return True
            else:
                self.logger.error("✗ Bootstrap failed")
                return False
                
        except Exception as e:
            self.logger.error(f"Bootstrap execution failed: {e}")
            return False
    
    def _setup_bootstrap_environment(self, chroot_dir: Path):
        """Setup environment for bootstrap execution"""
        self.logger.info("Setting up bootstrap environment")
        
        # Create chroot directory
        chroot_dir.mkdir(parents=True, exist_ok=True)
        
        # Create hooks directory
        hooks_dir = self.config.cache_dir / "hooks"
        hooks_dir.mkdir(exist_ok=True)
        
        # Create orchestrator integration hooks
        self._create_orchestrator_hooks(hooks_dir)
        
        self.logger.debug("Bootstrap environment setup completed")
        
    def _create_orchestrator_hooks(self, hooks_dir: Path):
        """Create hooks for orchestrator integration"""
        
        # Setup hook for orchestrator directories
        setup_hook = hooks_dir / "setup01-orchestrator.sh"
        setup_hook.write_text("""#!/bin/bash
# Orchestrator integration setup
echo "Setting up orchestrator integration"
mkdir -p "$1/opt/ultrathink"/{modules,config,cache}
mkdir -p "$1/etc/orchestrator"
mkdir -p "$1/var/log/orchestrator"
echo "mmdebstrap-orchestrator-python" > "$1/etc/orchestrator/bootstrap-method"
echo "$(date -Iseconds)" > "$1/etc/orchestrator/bootstrap-timestamp"
echo "3.0.0" > "$1/etc/orchestrator/integration-version"
""")
        setup_hook.chmod(0o755)
        
        # ZFS integration hook
        if self.config.enable_zfs:
            zfs_hook = hooks_dir / "setup02-zfs.sh"
            zfs_hook.write_text("""#!/bin/bash
# ZFS orchestrator integration
echo "Setting up ZFS orchestrator integration"
mkdir -p "$1/etc/zfs/orchestrator"
echo "enabled" > "$1/etc/zfs/orchestrator/integration-status"
echo "$(date -Iseconds)" > "$1/etc/zfs/orchestrator/setup-timestamp"
""")
            zfs_hook.chmod(0o755)
        
        # Security integration hook
        if self.config.enable_security:
            security_hook = hooks_dir / "setup03-security.sh"
            security_hook.write_text("""#!/bin/bash
# Security orchestrator integration
echo "Setting up security orchestrator integration"
mkdir -p "$1/etc/orchestrator/security"
echo "enabled" > "$1/etc/orchestrator/security/integration-status"
echo "$(date -Iseconds)" > "$1/etc/orchestrator/security/setup-timestamp"
""")
            security_hook.chmod(0o755)
        
        self.logger.debug(f"Created orchestrator hooks in {hooks_dir}")
    
    def _execute_mmdebstrap(self, chroot_dir: Path) -> bool:
        """Execute mmdebstrap with full orchestrator integration"""
        self.logger.info("Executing mmdebstrap with orchestrator features")
        
        # Get package list for build profile
        packages = self.PACKAGE_PROFILES[self.config.build_profile]
        include_packages = ",".join(packages)
        
        self.logger.info(f"Build profile: {self.config.build_profile.value}")
        self.logger.info(f"Package count: {len(packages)}")
        
        # Build mmdebstrap command
        cmd = [
            "mmdebstrap",
            "--arch", self.config.architecture,
            "--variant", "minbase",
            "--components", "main,restricted,universe,multiverse",
            "--include", include_packages,
            
            # Performance and reliability optimizations
            "--aptopt=Acquire::Check-Valid-Until \"false\"",
            "--aptopt=APT::Install-Recommends \"false\"", 
            "--aptopt=APT::Install-Suggests \"false\"",
            "--aptopt=Acquire::Languages \"none\"",
            "--aptopt=Acquire::Retries \"3\"",
            "--aptopt=Acquire::Timeout \"30\"",
            
            # Orchestrator hooks
            f"--hook-dir={self.config.cache_dir}/hooks",
            
            # System configuration
            "--customize-hook=rm \"$1/etc/resolv.conf\" || true",
            "--customize-hook=rm \"$1/etc/hostname\" || true", 
            "--customize-hook=echo \"UltraThink-ZFS-Live\" > \"$1/etc/hostname\"",
            "--customize-hook=echo \"127.0.1.1 UltraThink-ZFS-Live\" >> \"$1/etc/hosts\"",
            
            # Target and mirrors
            self.config.suite,
            str(chroot_dir)
        ]
        
        # Add mirrors
        cmd.extend(self.mirrors)
        
        # Log command for debugging (without sensitive info)
        self.logger.debug(f"mmdebstrap command: {' '.join(cmd[:10])}... (truncated)")
        
        # Execute with progress monitoring
        try:
            self.logger.info("Running mmdebstrap (estimated 3-8 minutes with 2-3x speedup)")
            start_time = datetime.now()
            
            # Create log file
            log_file = self.config.cache_dir / "mmdebstrap.log"
            
            with open(log_file, 'w') as log_f:
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )
                
                # Stream output with progress indicators
                output_lines = []
                for line_num, line in enumerate(iter(process.stdout.readline, '')):
                    line = line.rstrip()
                    if line:
                        log_f.write(line + '\n')
                        log_f.flush()
                        
                        # Show progress indicators
                        if line_num % 50 == 0:  # Every 50 lines
                            self.logger.info("mmdebstrap in progress...")
                        
                        # Log important messages
                        if any(keyword in line.lower() for keyword in ['error', 'warning', 'failed']):
                            if 'error' in line.lower():
                                self.logger.warning(f"mmdebstrap: {line}")
                            else:
                                self.logger.debug(f"mmdebstrap: {line}")
                        
                        output_lines.append(line)
                
                return_code = process.wait()
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            if return_code == 0:
                self.logger.info(f"✓ mmdebstrap completed successfully in {duration:.1f} seconds")
                return True
            else:
                self.logger.error(f"✗ mmdebstrap failed with return code {return_code}")
                self.logger.error(f"Check log file: {log_file}")
                
                # Show last few lines of output for debugging
                if output_lines:
                    self.logger.error("Last output lines:")
                    for line in output_lines[-5:]:
                        self.logger.error(f"  {line}")
                
                return False
                
        except subprocess.SubprocessError as e:
            self.logger.error(f"mmdebstrap execution error: {e}")
            return False
        except Exception as e:
            self.logger.error(f"Unexpected error during mmdebstrap: {e}")
            return False
    
    def _execute_debootstrap_fallback(self, chroot_dir: Path) -> bool:
        """Execute debootstrap as fallback method"""
        self.logger.warning("Using debootstrap fallback method")
        
        # Get limited package list for debootstrap compatibility
        packages = self.PACKAGE_PROFILES[self.config.build_profile]
        include_packages = ",".join(packages[:10])  # Limit for debootstrap
        
        cmd = [
            "debootstrap",
            "--arch", self.config.architecture,
            "--variant", "minbase",
            "--components", "main,restricted,universe,multiverse",
            "--include", include_packages,
            self.config.suite,
            str(chroot_dir),
            self.mirrors[0]  # Primary mirror only
        ]
        
        try:
            self.logger.info("Running debootstrap fallback (estimated 8-15 minutes)")
            start_time = datetime.now()
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800  # 30 minute timeout
            )
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            if result.returncode == 0:
                self.logger.info(f"✓ debootstrap fallback completed in {duration:.1f} seconds")
                
                # Create basic metadata for debootstrap
                metadata = {
                    "bootstrap_method": "debootstrap",
                    "timestamp": datetime.now().isoformat(),
                    "duration_seconds": duration
                }
                
                metadata_file = chroot_dir / "etc" / "bootstrap-info.json"
                metadata_file.parent.mkdir(parents=True, exist_ok=True)
                metadata_file.write_text(json.dumps(metadata, indent=2))
                
                return True
            else:
                self.logger.error(f"✗ debootstrap failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("debootstrap timed out after 30 minutes")
            return False
        except subprocess.SubprocessError as e:
            self.logger.error(f"debootstrap execution error: {e}")
            return False
    
    def _integrate_orchestrator_modules(self, chroot_dir: Path):
        """Integrate with orchestrator module system"""
        self.logger.info("Integrating with orchestrator modules")
        
        # Copy orchestrator modules to chroot
        modules_src = self.config.project_root / "src" / "modules"
        modules_dst = chroot_dir / "opt" / "ultrathink" / "modules"
        
        if modules_src.exists():
            modules_dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(modules_src, modules_dst, dirs_exist_ok=True)
            self.logger.debug("Orchestrator modules copied to chroot")
        
        # Setup chroot for orchestrator operations
        self._setup_chroot_mounts(chroot_dir)
        
        # Configure APT for orchestrator
        self._configure_orchestrator_apt(chroot_dir)
        
        self.logger.debug("Orchestrator module integration completed")
        
    def _setup_chroot_mounts(self, chroot_dir: Path):
        """Setup filesystem mounts for orchestrator operations"""
        mount_points = [
            ("proc", "proc"),
            ("sysfs", "sys"),
            ("devtmpfs", "dev"), 
            ("devpts", "dev/pts"),
            ("tmpfs", "run")
        ]
        
        for fs_type, mount_point in mount_points:
            full_path = chroot_dir / mount_point
            full_path.mkdir(parents=True, exist_ok=True)
            
            # Check if already mounted
            try:
                result = subprocess.run(
                    ["mountpoint", "-q", str(full_path)],
                    check=False,
                    capture_output=True
                )
                if result.returncode != 0:
                    # Not mounted, mount it
                    subprocess.run([
                        "mount", "-t", fs_type, "none", str(full_path)
                    ], check=True, capture_output=True)
                    self.logger.debug(f"Mounted {fs_type} on {mount_point}")
            except subprocess.CalledProcessError as e:
                self.logger.warning(f"Failed to mount {mount_point}: {e}")
    
    def _configure_orchestrator_apt(self, chroot_dir: Path):
        """Configure APT for orchestrator module installations"""
        
        # Enhanced sources.list
        sources_list = chroot_dir / "etc" / "apt" / "sources.list"
        sources_content = f"""# Ubuntu {self.config.suite} - orchestrator enhanced
deb {self.mirrors[0]} {self.config.suite} main restricted universe multiverse
deb {self.mirrors[0]} {self.config.suite}-updates main restricted universe multiverse
deb {self.mirrors[0]} {self.config.suite}-backports main restricted universe multiverse
"""
        
        if len(self.mirrors) > 1:
            sources_content += f"deb {self.mirrors[1]} {self.config.suite}-security main restricted universe multiverse\n"
        
        if self.config.enable_zfs:
            sources_content += f"# ZFS repository\ndeb https://ppa.launchpadcontent.net/jonathonf/zfs/ubuntu {self.config.suite} main\n"
        
        sources_list.write_text(sources_content)
        
        # APT configuration
        apt_conf_dir = chroot_dir / "etc" / "apt" / "apt.conf.d"
        apt_conf_dir.mkdir(parents=True, exist_ok=True)
        
        orchestrator_conf = apt_conf_dir / "99-orchestrator"
        orchestrator_conf.write_text("""# Orchestrator APT configuration
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::Assume-Yes "true";
Acquire::Languages "none";
Dpkg::Use-Pty "0";
Acquire::Retries "3";
Acquire::Timeout "30";
""")
        
        # Copy resolv.conf
        resolv_conf = chroot_dir / "etc" / "resolv.conf"
        if Path("/etc/resolv.conf").exists():
            shutil.copy2("/etc/resolv.conf", resolv_conf)
        
        self.logger.debug("APT configuration completed for orchestrator")
    
    def _create_bootstrap_metadata(self, chroot_dir: Path):
        """Create comprehensive metadata about the bootstrap process"""
        
        metadata = {
            "bootstrap_method": self.bootstrap_method.value,
            "orchestrator_integration": "python",
            "bootstrap_timestamp": datetime.now().isoformat(),
            "build_profile": self.config.build_profile.value,
            "orchestrator_version": "3.0.0",
            "configuration": {
                "suite": self.config.suite,
                "architecture": self.config.architecture,
                "zfs_enabled": self.config.enable_zfs,
                "security_enabled": self.config.enable_security,
                "mirrors": self.mirrors
            },
            "packages": {
                "profile": self.config.build_profile.value,
                "count": len(self.PACKAGE_PROFILES[self.config.build_profile]),
                "list": self.PACKAGE_PROFILES[self.config.build_profile]
            }
        }
        
        # Write metadata to chroot
        metadata_file = chroot_dir / "etc" / "bootstrap-info.json"
        metadata_file.write_text(json.dumps(metadata, indent=2))
        
        # Write orchestrator-specific metadata
        orchestrator_metadata = chroot_dir / "etc" / "orchestrator" / "bootstrap.json"
        orchestrator_metadata.parent.mkdir(parents=True, exist_ok=True)
        orchestrator_metadata.write_text(json.dumps(metadata, indent=2))
        
        self.logger.info("Bootstrap metadata created")
        
        return metadata
    
    def _verify_bootstrap_result(self, chroot_dir: Path):
        """Verify bootstrap completed successfully"""
        self.logger.info("Verifying bootstrap result")
        
        # Check essential files
        essential_files = [
            chroot_dir / "bin" / "bash",
            chroot_dir / "etc" / "os-release",
            chroot_dir / "usr" / "bin" / "apt",
            chroot_dir / "bin" / "systemctl"
        ]
        
        missing_files = []
        for file_path in essential_files:
            if not file_path.exists():
                missing_files.append(str(file_path))
        
        if missing_files:
            raise RuntimeError(f"Essential files missing: {missing_files}")
        
        # Verify system release
        try:
            result = subprocess.run(
                ["chroot", str(chroot_dir), "lsb_release", "-cs"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                chroot_release = result.stdout.strip()
                self.logger.info(f"Bootstrap verification: {chroot_release} system created")
                
                if chroot_release != self.config.suite:
                    self.logger.warning(f"Release mismatch: expected {self.config.suite}, got {chroot_release}")
            else:
                self.logger.warning("Could not verify system release")
                
        except subprocess.TimeoutExpired:
            self.logger.warning("Release verification timed out")
        except Exception as e:
            self.logger.warning(f"Release verification failed: {e}")
        
        # Check orchestrator metadata
        if (chroot_dir / "etc" / "bootstrap-info.json").exists():
            self.logger.info("✓ Bootstrap metadata created")
        
        if (chroot_dir / "etc" / "orchestrator" / "bootstrap-method").exists():
            self.logger.info("✓ Orchestrator integration verified")
        
        self.logger.info("✓ Bootstrap verification completed successfully")

def main():
    """Main entry point for standalone execution"""
    parser = argparse.ArgumentParser(
        description="mmdebstrap Python Orchestrator Integration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --chroot-dir /tmp/chroot
  %(prog)s --chroot-dir /tmp/chroot --suite noble --profile development
  %(prog)s --chroot-dir /tmp/chroot --enable-zfs 1 --profile zfs_optimized

Build Profiles:
  minimal       - Essential packages only
  standard      - Common utilities and tools
  development   - Full development environment
  zfs_optimized - ZFS support with optimization tools
  security      - Security hardening packages
        """
    )
    
    # Required arguments
    parser.add_argument("--chroot-dir", required=True,
                       help="Target chroot directory path")
    parser.add_argument("--project-root", required=True,
                       help="Project root directory path")
    
    # Optional configuration
    parser.add_argument("--suite", default="noble",
                       help="Ubuntu suite (default: noble)")
    parser.add_argument("--arch", default="amd64",
                       help="Target architecture (default: amd64)")
    parser.add_argument("--profile", default="standard",
                       choices=[p.value for p in BuildProfile],
                       help="Build profile (default: standard)")
    
    # Feature flags
    parser.add_argument("--enable-zfs", type=int, default=0,
                       help="Enable ZFS integration (0/1, default: 0)")
    parser.add_argument("--enable-security", type=int, default=0,
                       help="Enable security integration (0/1, default: 0)")
    
    # Debugging
    parser.add_argument("--debug", action="store_true",
                       help="Enable debug logging")
    
    args = parser.parse_args()
    
    # Setup logging level
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.info("Debug logging enabled")
    
    # Create configuration
    config = BootstrapConfig(
        suite=args.suite,
        architecture=args.arch,
        build_profile=BuildProfile(args.profile),
        enable_zfs=bool(args.enable_zfs),
        enable_security=bool(args.enable_security),
        project_root=Path(args.project_root)
    )
    
    # Create orchestrator and execute bootstrap
    orchestrator = MmdebstrapOrchestrator(config)
    
    logger.info(f"Starting mmdebstrap orchestrator v3.0.0")
    logger.info(f"Configuration: {config.suite}/{config.architecture}/{config.build_profile.value}")
    logger.info(f"Target: {args.chroot_dir}")
    
    try:
        success = orchestrator.execute_bootstrap(Path(args.chroot_dir))
        
        if success:
            logger.info("✓ Bootstrap completed successfully")
            print(f"SUCCESS: Bootstrap completed at {args.chroot_dir}")
            sys.exit(0)
        else:
            logger.error("✗ Bootstrap failed")
            print(f"FAILED: Bootstrap failed for {args.chroot_dir}")
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.warning("Bootstrap interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
