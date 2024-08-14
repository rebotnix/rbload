![rb_load_rebotnix_opensource](https://github.com/user-attachments/assets/e1dc4f22-664e-465e-93ee-5ffaf1c2645b)

# REBOTNIX RB-Load

## Overview

The REBOTNIX RB-Load is a multi-parallel thread application designed for stress testing NVIDIA Orin SoCs (System on Chip). This tool allows you to fully load either all ARM CPU cores, all GPU cores, or both simultaneously under controlled conditions. It is especially useful for developers and engineers who need to assess the performance, stability, and thermal characteristics, particularly in demanding environments.

To download the binary, go to the release section.
https://github.com/rebotnix/rbload/releases

## Features

- **CPU Stress Testing:** Fully utilizes all ARM CPU cores to evaluate performance and thermal characteristics.
- **GPU Stress Testing:** Leverages CUDA to stress all GPU cores, ideal for testing the thermal limits and stability of the graphics processor.
- **Combined CPU & GPU Stress Testing:** Simultaneously stresses both the CPU and GPU, providing a comprehensive test of system stability.
- **Temperature Monitoring:** Real-time monitoring of GPU and CPU temperatures using `tegrastats`, giving you immediate feedback during the stress test.
- **Logging:** Option to log temperature data at regular intervals, allowing for detailed analysis of system performance over time.
- **Compact Static Binary:** The entire application is packaged into a static binary using `rb-compress`, reducing its size to just 204 KB.
- **Compatibility:** Requires NO additional tools like PyTorch or similar frameworks to be installed for proper execution.

## Usage
unpack the zip file from the asset release.

Example:
unzip rbload.zip

Set chmod 755 to rbload. No installation is required.


### Release Information

The REBOTNIX RB-Load is scheduled to be released in September 2024. This release will include detailed documentation and instructions on how to integrate the tool into your testing workflows.

### Running the Tool

The tool can be executed with various options to customize the stress test:

```bash
./rbload -m=<mode> -t=<duration> -stats=<true|false> -o=<output_filename>
```

Parameters
-m=<mode>: Specifies the stress test mode.

0: CPU only stress test.
1: GPU only stress test.
2: Combined CPU and GPU stress test.
-t=<duration>: Duration of the stress test in seconds (default is 60 seconds).

-stats=<true|false>: Enables or disables logging of temperature statistics to a file (default is true).

-o=<output_filename>: Specifies the name of the output file where temperature data will be logged.

License: MIT
