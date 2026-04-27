#!/usr/bin/env python3
import subprocess
import os
import sys

os.chdir(r'E:\DoT\SHREY')

try:
    print("Building with CMake...")
    result = subprocess.run(['cmake', '--build', 'cmake-build-debug'], 
                          capture_output=True, text=True, timeout=300)
    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)
    
    if result.returncode != 0:
        print("CMake build failed, trying Ninja directly...")
        os.chdir('cmake-build-debug')
        result = subprocess.run(['ninja'], capture_output=True, text=True, timeout=300)
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        sys.exit(result.returncode)
    
    print("\n✅ Build successful!")
    sys.exit(0)
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
