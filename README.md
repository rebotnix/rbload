# RB-Load Stress Tool

REBOTNIX RB-LOAD STRESS TOOLS for NVIDIA Jetson
Written by Gary Hilgemann for REBOTNIX, Germany

## Prerequisites

- NVIDIA Jetson familiy
- CUDA Toolkit installed
- GCC/G++ compiler
- Make build system

## Features

- Real-time temperature monitoring with selectable units (Celsius/Fahrenheit)
- Configurable test duration
- Temperature logging to file
- CUDA-based GPU stress testing
- Multi-threaded CPU stress testing
- Comprehensive system temperature monitoring

## Compilation Instructions

1. First, make sure you have the correct CUDA toolkit installed:
```bash
nvcc --version
```

2. Adjust the Makefile according to your Jetson model:
- Jetson Nano: ARCH = -arch=sm_53
- Jetson Xavier NX: ARCH = -arch=sm_72
- Jetson AGX Xavier: ARCH = -arch=sm_72
- Jetson TX2: ARCH = -arch=sm_62

3. Compile the program:
```bash
make
```

4. The compilation will create an executable named 'rbload'

## Usage

Run the stress test tool with the following options:
```bash
./rbload -m=[mode] -t=[duration] -stats=[true/false] -o=[output_file] -unit=[C/F]
```

Parameters:
- `-m`: Test mode (0=CPU, 1=GPU, 2=Both)
- `-t`: Test duration in seconds
- `-stats`: Enable/disable temperature logging
- `-o`: Output log file name
- `-unit`: Temperature unit (C=Celsius [default], F=Fahrenheit)

Examples:
```bash
# Run with default Celsius temperature display
./rbload -m=2 -t=60 -stats=true -o=stress_test_log.txt

# Run with Fahrenheit temperature display
./rbload -m=2 -t=60 -stats=true -o=stress_test_log.txt -unit=F
```

## Test Modes

1. **CPU Only (mode 0)**
   - Stresses all CPU cores with intensive calculations
   - Monitors CPU temperature

2. **GPU Only (mode 1)**
   - Executes CUDA kernels to stress the GPU
   - Monitors GPU temperature

3. **Combined (mode 2)**
   - Stresses both CPU and GPU simultaneously
   - Monitors both temperatures

## Temperature Monitoring

- Real-time display of both CPU and GPU temperatures
- Choose between Celsius (default) and Fahrenheit
- Temperature logging to file when stats=true
- Automatic detection of temperature sensors

## Cleaning

To clean the build:
```bash
make clean
```

## Troubleshooting

1. If you get compilation errors about CUDA architecture, verify your Jetson model and adjust the ARCH variable in the Makefile accordingly.

2. Make sure you have proper permissions to read the temperature sensors:
```bash
sudo chmod a+r /sys/class/thermal/thermal_zone*/temp
```

3. Ensure you have sufficient permissions to run the program:
```bash
chmod +x rbload
```

# REBOTNIX RB-LOAD Stresstest Software Documentation

## Overview
RB-LOAD is a software tool designed to stress-test high-performance computing systems, specifically those equipped with NVIDIA Tegra-based processors. It executes demanding computations on the GPU and/or CPU to assess the performance and stability under extreme workload conditions. The program also provides continuous monitoring of GPU and CPU temperatures, which is crucial for identifying thermal issues and potential overheating scenarios.

## Features
1. **GPU Stress Test**
   - Executes intensive computations on the GPU to test its performance capabilities and thermal response under load.
2. **CPU Stress Test**
   - Stresses all CPU cores with complex calculations to examine CPU performance and thermal characteristics.
3. **Combined GPU and CPU Stress Test**
   - Integrates both tests to provide a comprehensive assessment of the system's performance under simulated peak load conditions.
4. **Temperature Monitoring**
   - Monitors and logs GPU and CPU temperatures in real-time during testing.
5. **Logging**
   - Continuously logs temperature data and test results every 10 seconds to a file for later analysis, ensuring a detailed record of the system's performance and thermal conditions throughout the test.

## System Requirements
- **Operating System:** Linux, specifically developed for systems with NVIDIA Tegra processors (such as NVIDIA Jetson platforms).
- **Software Dependencies:** CUDA-capable GPU, CUDA Toolkit, and `tegrastats` for temperature monitoring.
- **Compiler:** G++ for C++17 or newer to compile the code.
- **Hardware:** NVIDIA GPU (for GPU-related tests), multi-core CPU.

## Installation and Configuration
1. **Install CUDA Toolkit**
   - Ensure the CUDA Toolkit is installed on your system to utilize GPU functionalities.
2. **Configure Compiler**
   - The source code must be compiled with a modern C++ compiler that supports C++17.
3. **Install tegrastats**
   - This tool should be installed on your system as it is used for monitoring temperature data.

## Usage
To start the program, execute it with optional command line arguments to specify the mode and duration of the test. 

Example:
./rbload 1 120 true

- `1` sets the mode (1: GPU only, 2: CPU only, 3: both GPU and CPU).
- `120 (2 Minutes) is the test duration in seconds.
- `true` enables logging of temperature data.

## Safety Precautions
- **Monitoring:** Continuously monitor temperature and system performance to prevent damage due to overheating.
- **Use at Your Own Risk:** The software is powerful and can push hardware to its limits. Therefore, use is at your own risk.

## License
The software is copyrighted and may only be used according to the license agreement set by the author.

## Support
For technical support and more information, please contact the software developer or visit our website.

## License
This project is licensed under the AGPL-3.0 License – see the [LICENSE](./LICENSE) file for details.

