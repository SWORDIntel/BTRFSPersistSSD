#!/usr/bin/env python3
"""
mmdebstrap Orchestrator Python Integration
Provides Python interface for mmdebstrap operations within the build orchestrator

Features:
- Command-line interface for mmdebstrap operations
- Configuration file support
- Integration with shell-based modules
- Progress monitoring and logging
- Profile-based builds
- Automatic fallback support

Author: Build Orchestrator Integration Team
Version: 3.1.0
Date: 2025-08-27
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
import yaml
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any


class MmdebstrapOrchestrator:
    """Main orchestrator class for mmdebstrap operations"""
    
    def __init__(self, project_root: Optional[str] = None, config_file: Optional[str] = None):
        """Initialize the orchestrator"""
        self.version = "3.1.0"
        self.project_root = Path(project_root or os.getcwd())
        
        # Configuration
        self.config_file = config_file or self.project_root / "src/config/mmdebstrap/mmdebstrap_profiles_config.yaml"
        self.config = self.load_configuration()
        
        # Setup logging
        self.setup_logging()
        
        # Module paths
        self.module_path = self.project_root / "src/modules/mmdebstrap/orchestrator.sh"
        self.cache_dir = self.project_root / "cache/mmdebstrap"
        
        # State tracking
        self.current_operation = None
        self.start_time = None
        
        self.logger.info(f"mmdebstrap Orchestrator v{self.version} initialized")
        self.logger.info(f"Project root: {self.project_root}")
        self.logger.info(f"Configuration: {self.config_file}")
    
    def load_configuration(self) -> Dict[str, Any]:
        """Load configuration from YAML file"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = yaml.safe_load(f)
                return config
            else:
                # Default configuration
                return {
                    'profiles': {
                        'minimal': {'packages': ['systemd', 'dbus', 'apt-utils']},
                        'standard': {'packages': ['systemd', 'dbus', 'apt-utils', 'sudo', 'curl']},
                        'development': {'packages': ['systemd', 'dbus', 'build-essential', 'git']},
                        'zfs_optimized': {'packages': ['systemd', 'dbus', 'zfsutils-linux']},
                        'security': {'packages': ['systemd', 'dbus', 'cryptsetup', 'fail2ban']}
                    },
                    'global': {
                        'default_suite': 'noble',
                        'default_arch': 'amd64',
                        'default_profile': 'standard'
                    }
                }
        except Exception as e:
            print(f"Warning: Failed to load configuration: {e}")
            return {}
    
    def setup_logging(self) -> None:
        """Setup logging configuration"""
        log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
        log_dir = self.project_root / "logs"
        log_dir.mkdir(exist_ok=True)
        
        # Configure logging
        logging.basicConfig(
            level=getattr(logging, log_level),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_dir / "mmdebstrap-orchestrator.log"),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        self.logger = logging.getLogger('mmdebstrap_orchestrator')
    
    def check_prerequisites(self) -> Tuple[bool, List[str]]:
        """Check system prerequisites"""
        issues = []
        
        # Check for required commands
        commands = ['mmdebstrap', 'debootstrap', 'systemd-nspawn']
        for cmd in commands:
            if not self.command_exists(cmd):
                if cmd == 'mmdebstrap':
                    self.logger.warning(f"Command not found: {cmd} (will use debootstrap fallback)")
                else:
                    issues.append(f"Required command not found: {cmd}")
        
        # Check module file
        if not self.module_path.exists():
            issues.append(f"mmdebstrap module not found: {self.module_path}")
        
        # Check project structure
        required_dirs = ['src/modules', 'cache', 'logs']
        for dir_path in required_dirs:
            full_path = self.project_root / dir_path
            if not full_path.exists():
                self.logger.warning(f"Creating missing directory: {full_path}")
                full_path.mkdir(parents=True, exist_ok=True)
        
        return len(issues) == 0, issues
    
    @staticmethod
    def command_exists(command: str) -> bool:
        """Check if a command exists in PATH"""
        return subprocess.run(['which', command], capture_output=True).returncode == 0
    
    def get_available_profiles(self) -> List[str]:
        """Get list of available build profiles"""
        return list(self.config.get('profiles', {}).keys())
    
    def get_profile_info(self, profile: str) -> Optional[Dict[str, Any]]:
        """Get information about a specific profile"""
        return self.config.get('profiles', {}).get(profile)
    
    def validate_parameters(self, chroot_dir: str, suite: str, arch: str, profile: str) -> Tuple[bool, List[str]]:
        """Validate bootstrap parameters"""
        errors = []
        
        # Validate chroot directory
        chroot_path = Path(chroot_dir)
        if not chroot_path.parent.exists():
            errors.append(f"Parent directory does not exist: {chroot_path.parent}")
        
        # Validate profile
        if profile not in self.get_available_profiles():
            errors.append(f"Unknown profile: {profile}. Available: {', '.join(self.get_available_profiles())}")
        
        # Validate suite (basic check)
        valid_suites = ['focal', 'jammy', 'noble', 'mantic', 'lunar']
        if suite not in valid_suites:
            self.logger.warning(f"Suite '{suite}' not in common list: {valid_suites}")
        
        # Validate architecture
        valid_arches = ['amd64', 'arm64', 'armhf', 'i386']
        if arch not in valid_arches:
            self.logger.warning(f"Architecture '{arch}' not in common list: {valid_arches}")
        
        return len(errors) == 0, errors
    
    def execute_shell_module(self, chroot_dir: str, suite: str, arch: str, profile: str) -> bool:
        """Execute the shell-based mmdebstrap module"""
        self.logger.info("Executing shell-based mmdebstrap module")
        
        # Prepare environment
        env = os.environ.copy()
        env.update({
            'PROJECT_ROOT': str(self.project_root),
            'CHROOT_DIR': chroot_dir,
            'BUILD_SUITE': suite,
            'BUILD_ARCH': arch,
            'BUILD_PROFILE': profile
        })
        
        # Prepare shell command
        shell_cmd = f"""
        source "{self.module_path}"
        orchestrator_mmdebstrap_bootstrap "{chroot_dir}" "{suite}" "{arch}" "{profile}"
        """
        
        try:
            # Execute with progress monitoring
            process = subprocess.Popen(
                ['bash', '-c', shell_cmd],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )
            
            # Monitor output
            for line in iter(process.stdout.readline, ''):
                line = line.rstrip()
                if line:
                    self.logger.info(f"SHELL: {line}")
            
            # Wait for completion
            return_code = process.wait()
            
            if return_code == 0:
                self.logger.info("Shell module execution completed successfully")
                return True
            else:
                self.logger.error(f"Shell module execution failed with exit code: {return_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error executing shell module: {e}")
            return False
    
    def bootstrap(self, chroot_dir: str, suite: Optional[str] = None, arch: Optional[str] = None, 
                  profile: Optional[str] = None, force: bool = False) -> bool:
        """Execute bootstrap operation"""
        
        # Use defaults from configuration
        global_config = self.config.get('global', {})
        suite = suite or global_config.get('default_suite', 'noble')
        arch = arch or global_config.get('default_arch', 'amd64')
        profile = profile or global_config.get('default_profile', 'standard')
        
        self.logger.info("=== Starting Bootstrap Operation ===")
        self.logger.info(f"Target: {chroot_dir}")
        self.logger.info(f"Suite: {suite}")
        self.logger.info(f"Architecture: {arch}")
        self.logger.info(f"Profile: {profile}")
        self.logger.info(f"Force: {force}")
        
        # Track operation
        self.current_operation = "bootstrap"
        self.start_time = time.time()
        
        # Check prerequisites
        prereq_ok, prereq_issues = self.check_prerequisites()
        if not prereq_ok:
            self.logger.error("Prerequisites check failed:")
            for issue in prereq_issues:
                self.logger.error(f"  - {issue}")
            return False
        
        # Validate parameters
        valid, errors = self.validate_parameters(chroot_dir, suite, arch, profile)
        if not valid:
            self.logger.error("Parameter validation failed:")
            for error in errors:
                self.logger.error(f"  - {error}")
            return False
        
        # Check if target exists
        chroot_path = Path(chroot_dir)
        if chroot_path.exists() and not force:
            self.logger.error(f"Target directory already exists: {chroot_dir}")
            self.logger.error("Use --force to overwrite or choose a different target")
            return False
        
        if chroot_path.exists() and force:
            self.logger.warning(f"Removing existing target directory: {chroot_dir}")
            subprocess.run(['rm', '-rf', str(chroot_path)], check=True)
        
        # Execute bootstrap
        success = self.execute_shell_module(chroot_dir, suite, arch, profile)
        
        # Calculate duration
        duration = time.time() - self.start_time if self.start_time else 0
        
        if success:
            self.logger.info(f"=== Bootstrap Completed Successfully ({duration:.1f}s) ===")
            
            # Post-bootstrap information
            if chroot_path.exists():
                size = self.get_directory_size(chroot_path)
                self.logger.info(f"Bootstrap directory size: {size}")
                
                # Create completion marker
                marker_file = chroot_path / ".bootstrap-complete"
                with open(marker_file, 'w') as f:
                    f.write(json.dumps({
                        'completed': time.time(),
                        'suite': suite,
                        'arch': arch,
                        'profile': profile,
                        'duration': duration,
                        'method': 'mmdebstrap',
                        'version': self.version
                    }, indent=2))
        else:
            self.logger.error(f"=== Bootstrap Failed ({duration:.1f}s) ===")
        
        return success
    
    @staticmethod
    def get_directory_size(path: Path) -> str:
        """Get human-readable directory size"""
        try:
            result = subprocess.run(['du', '-sh', str(path)], capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.split()[0]
        except Exception:
            pass
        return "unknown"
    
    def list_profiles(self) -> None:
        """List available build profiles"""
        profiles = self.config.get('profiles', {})
        
        print("\nAvailable Build Profiles:")
        print("=" * 50)
        
        for profile_name, profile_config in profiles.items():
            description = profile_config.get('description', 'No description available')
            packages = profile_config.get('packages', [])
            
            print(f"\n{profile_name}:")
            print(f"  Description: {description}")
            print(f"  Packages: {len(packages)} packages")
            
            if len(packages) <= 10:
                print(f"  Package list: {', '.join(packages)}")
            else:
                print(f"  Sample packages: {', '.join(packages[:10])}...")
        
        print()
    
    def show_config(self) -> None:
        """Show current configuration"""
        print(f"\nmmdebstrap Orchestrator Configuration")
        print("=" * 50)
        print(f"Version: {self.version}")
        print(f"Project Root: {self.project_root}")
        print(f"Configuration File: {self.config_file}")
        print(f"Module Path: {self.module_path}")
        print(f"Cache Directory: {self.cache_dir}")
        
        # Global configuration
        global_config = self.config.get('global', {})
        if global_config:
            print(f"\nGlobal Settings:")
            for key, value in global_config.items():
                print(f"  {key}: {value}")
        
        # Available profiles
        profiles = list(self.config.get('profiles', {}).keys())
        print(f"\nAvailable Profiles ({len(profiles)}): {', '.join(profiles)}")
        
        print()
    
    def validate_system(self) -> bool:
        """Validate system configuration and dependencies"""
        print(f"\nmmdebstrap Orchestrator System Validation")
        print("=" * 50)
        
        # Check prerequisites
        prereq_ok, issues = self.check_prerequisites()
        
        print(f"Prerequisites: {'✓ PASS' if prereq_ok else '✗ FAIL'}")
        if not prereq_ok:
            for issue in issues:
                print(f"  ✗ {issue}")
        
        # Check commands
        commands = [
            ('mmdebstrap', 'Primary bootstrap tool'),
            ('debootstrap', 'Fallback bootstrap tool'),
            ('systemd-nspawn', 'Container support'),
            ('python3', 'Python interpreter'),
            ('bash', 'Shell interpreter')
        ]
        
        print(f"\nCommand Availability:")
        for cmd, desc in commands:
            available = self.command_exists(cmd)
            status = '✓' if available else '✗'
            print(f"  {status} {cmd}: {desc}")
        
        # Check files and directories
        paths = [
            (self.module_path, 'mmdebstrap module'),
            (self.config_file, 'Configuration file'),
            (self.project_root / 'src/modules', 'Modules directory'),
            (self.cache_dir, 'Cache directory')
        ]
        
        print(f"\nFile System:")
        for path, desc in paths:
            exists = path.exists()
            status = '✓' if exists else '✗'
            print(f"  {status} {desc}: {path}")
        
        # Configuration validation
        print(f"\nConfiguration:")
        profiles = self.config.get('profiles', {})
        print(f"  ✓ {len(profiles)} profiles configured")
        
        global_config = self.config.get('global', {})
        if global_config:
            print(f"  ✓ Global configuration present")
        else:
            print(f"  ✗ No global configuration")
        
        print(f"\nOverall Status: {'✓ READY' if prereq_ok else '✗ NEEDS ATTENTION'}")
        print()
        
        return prereq_ok


def create_argument_parser() -> argparse.ArgumentParser:
    """Create command line argument parser"""
    parser = argparse.ArgumentParser(
        description='mmdebstrap Orchestrator Python Interface',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic bootstrap
  python3 mmdebstrap_orchestrator.py bootstrap /tmp/chroot

  # Custom configuration
  python3 mmdebstrap_orchestrator.py bootstrap /tmp/chroot \\
    --suite noble --arch amd64 --profile development

  # List available profiles
  python3 mmdebstrap_orchestrator.py list-profiles

  # System validation
  python3 mmdebstrap_orchestrator.py validate

  # Show configuration
  python3 mmdebstrap_orchestrator.py show-config
        """
    )
    
    parser.add_argument('--version', action='version', version='mmdebstrap Orchestrator 3.1.0')
    parser.add_argument('--project-root', help='Project root directory')
    parser.add_argument('--config', help='Configuration file path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Bootstrap command
    bootstrap_parser = subparsers.add_parser('bootstrap', help='Execute bootstrap operation')
    bootstrap_parser.add_argument('chroot_dir', help='Target chroot directory')
    bootstrap_parser.add_argument('--suite', help='Ubuntu/Debian suite (default: noble)')
    bootstrap_parser.add_argument('--arch', help='Target architecture (default: amd64)')
    bootstrap_parser.add_argument('--profile', help='Build profile (default: standard)')
    bootstrap_parser.add_argument('--force', action='store_true', help='Force overwrite existing directory')
    
    # Utility commands
    subparsers.add_parser('list-profiles', help='List available build profiles')
    subparsers.add_parser('show-config', help='Show current configuration')
    subparsers.add_parser('validate', help='Validate system configuration')
    
    return parser


def main() -> int:
    """Main entry point"""
    parser = create_argument_parser()
    args = parser.parse_args()
    
    # Set logging level
    if args.verbose:
        os.environ['LOG_LEVEL'] = 'DEBUG'
    
    try:
        # Initialize orchestrator
        orchestrator = MmdebstrapOrchestrator(
            project_root=args.project_root,
            config_file=args.config
        )
        
        # Execute command
        if args.command == 'bootstrap':
            success = orchestrator.bootstrap(
                chroot_dir=args.chroot_dir,
                suite=args.suite,
                arch=args.arch,
                profile=args.profile,
                force=args.force
            )
            return 0 if success else 1
            
        elif args.command == 'list-profiles':
            orchestrator.list_profiles()
            return 0
            
        elif args.command == 'show-config':
            orchestrator.show_config()
            return 0
            
        elif args.command == 'validate':
            success = orchestrator.validate_system()
            return 0 if success else 1
            
        else:
            parser.print_help()
            return 1
            
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
        return 1
    except Exception as e:
        print(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())