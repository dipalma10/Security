#!/usr/bin/env python3
import subprocess
import sys
import shutil
import os

def run(cmd, check=True):
    print(f"[+] Running: {cmd}")
    res = subprocess.run(cmd, shell=True)
    if check and res.returncode != 0:
        print(f"[-] Command failed with exit code {res.returncode}: {cmd}")
        sys.exit(res.returncode)

def main():
    if os.geteuid() != 0:
        print("[-] Please run this setup script with sudo.")
        sys.exit(1)

    print("=== Step 1: Verify User Namespace Support ===")
    # Modern kernels have unprivileged_userns enabled by default.
    # We check the standard sysctl parameter if present, otherwise continue.
    sysctl_path = "/proc/sys/kernel/unprivileged_userns_clone"
    if os.path.exists(sysctl_path):
        run("sysctl -w kernel.unprivileged_userns_clone=1")
    else:
        print("[*] Modern kernel detected: unprivileged user namespaces are active by default.")

    print("\n=== Step 2: Install Build Dependencies ===")
    run("apt update && apt install -y build-essential cargo git python3 python3-pip")

    print("\n=== Step 3: Load TUN Kernel Module ===")
    run("modprobe tun")

    print("\n=== Step 4: Clone & Build oniux ===")
    build_dir = "/tmp/oniux_build"
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    
    run(f"git clone https://github.com/limitcool/oniux.git {build_dir}")
    os.chdir(build_dir)
    run("cargo build --release")

    print("\n=== Step 5: Install Executable ===")
    binary_source = os.path.join(build_dir, "target/release/oniux")
    binary_dest = "/usr/local/bin/oniux"
    shutil.copy(binary_source, binary_dest)
    os.chmod(binary_dest, 0o755)

    print(f"\n[✓] oniux successfully installed to {binary_dest}!")
    print("Verify by running: oniux --help")

if __name__ == "__main__":
    main()
