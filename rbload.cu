/*
REBOTNIX RB-LOAD STRESS TOOLS
WRITTEN BY GARY HILGEMANN FOR REBOTNIX, GERMANY
ALL RIGHTS RESERVED 2024-now.
USE WITH OWN RISK.

Description:
This tool is designed to stress test both CPU and GPU components of a NVIDIA Jetson.
It provides three modes of operation:
- Mode 0: CPU-only stress test
- Mode 1: GPU-only stress test
- Mode 2: Combined CPU and GPU stress test

Features:
- Real-time temperature monitoring
- Configurable test duration
- Temperature logging to file
- CUDA-based GPU stress testing
- Multi-threaded CPU stress testing
- Selectable temperature units (Celsius/Fahrenheit)

Usage:
rbload -m=[mode] -t=[duration] -stats=[true/false] -o=[output_file] -unit=[C/F]

Parameters:
-m=[mode]      : Test mode (0=CPU, 1=GPU, 2=Both)
-t=[duration]  : Test duration in seconds
-stats=[bool]  : Enable/disable temperature logging
-o=[filename]  : Output log file name
-unit=[C/F]    : Temperature unit (C=Celsius [default], F=Fahrenheit)

Example:
rbload -m=2 -t=60 -stats=true -o=stress_test_log.txt -unit=C

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
*/

#include <iostream>
#include <cuda_runtime.h>
#include <thread>
#include <chrono>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <sstream>
#include <fstream>
#include <cstdio>
#include <string>
#include <atomic>
#include <ctime>
#include <mutex>
#include <map>
#include <memory>

// ANSI color codes for terminal output formatting
#define RESET "\033[0m"    // Reset text formatting
#define WHITE "\033[37m"   // White text color
#define GREEN "\033[32m"   // Green text color

/**
 * RAII wrapper for pipe management used in temperature monitoring
 * Ensures proper cleanup of pipe resources through RAII pattern
 */
class PipeRAII {
private:
    FILE* pipe;    // File pointer for the pipe
public:
    /**
     * Constructor: Opens a pipe with the specified command
     * @param command Shell command to execute
     */
    PipeRAII(const char* command) : pipe(popen(command, "r")) {}

    /**
     * Destructor: Ensures pipe is properly closed
     */
    ~PipeRAII() { if (pipe) pclose(pipe); }

    /**
     * @return Raw file pointer to the pipe
     */
    FILE* get() { return pipe; }

    /**
     * @return true if pipe was successfully opened, false otherwise
     */
    bool isValid() const { return pipe != nullptr; }
};

/**
 * CUDA kernel for GPU stress testing
 * Performs intensive floating-point calculations in parallel on the GPU
 * Each thread performs a series of arithmetic operations in a loop
 * 
 * @param data Pointer to device memory array for calculations
 * @param N Size of the array (number of elements)
 */
__global__ void gpuStressTest(float *data, int N) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {
        float x = data[idx];
        // Perform intensive floating-point calculations
        for (int i = 0; i < 1000000; ++i) {
            x = x * x - x + 2.0f;  // Arbitrary computation to stress GPU, simple but works good
        }
        data[idx] = x;
    }
}

std::string readFileContent(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        return "N/A";
    }
    std::string content;
    std::getline(file, content);
    file.close();
    return content;
}

int readTemperature(const std::string& path) {
    std::string content = readFileContent(path);
    try {
        return std::stoi(content) / 1000; // Convert from millicelsius to celsius
    } catch (...) {
        return -1;
    }
}

// Add temperature conversion function
float celsiusToFahrenheit(float celsius) {
    return (celsius * 9.0f / 5.0f) + 32.0f;
}

// Add temperature unit enum
enum class TempUnit {
    Celsius,
    Fahrenheit
};

// Add configurable logging interval (default 5s, minimum 1s)
int loggingInterval = 5;

struct ThermalZone {
    std::string path;
    std::string type;
    int temp;
};

// Function to scan and categorize thermal zones
std::vector<ThermalZone> scanThermalZones() {
    std::vector<ThermalZone> zones;
    
    // Use popen to execute the shell command and read results
    // We want to support any jetson modules, let scan all zones
    // gpu-thermal,cv0-thermal,cv1-thermal,cv2-thermal,soc0-thermal,soc1-thermal,soc2-thermal,tj-thermal
    const char* cmd = "ls -d /sys/class/thermal/thermal_zone*";
    PipeRAII pipe(cmd);
    
    if (!pipe.isValid()) {
        return zones;
    }

    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe.get())) {
        // Remove newline
        std::string zonePath(buffer);
        zonePath = zonePath.substr(0, zonePath.find_last_not_of("\n\r") + 1);
        
        // Read zone type
        std::string typeFile = zonePath + "/type";
        std::string type = readFileContent(typeFile);
        if (type != "N/A") {
            zones.push_back({zonePath, type, -1});
        }
    }
    
    return zones;
}

// Function to update temperatures for thermal zones
void updateTemperatures(std::vector<ThermalZone>& zones) {
    for (auto& zone : zones) {
        std::string tempFile = zone.path + "/temp";
        zone.temp = readTemperature(tempFile);
    }
}

// Function to get temperature for a specific thermal type
int getTypeTemperature(const std::vector<ThermalZone>& zones, const std::string& type) {
    int max_temp = -1;
    for (const auto& zone : zones) {
        if (zone.type == type && zone.temp > max_temp) {
            max_temp = zone.temp;
        }
    }
    return max_temp;
}

void monitorTemperatures(std::atomic<bool>& running, std::string& gpuTemp, std::string& cpuTemp, 
                        std::mutex& mtx, TempUnit unit = TempUnit::Celsius) {
    // Initial scan of thermal zones
    std::vector<ThermalZone> thermalZones = scanThermalZones();
    
    if (thermalZones.empty()) {
        std::cerr << "Warning: No thermal zones found!" << std::endl;
        return;
    }

    while (running) {
        // Update all temperatures
        updateTemperatures(thermalZones);

        // Get temperatures for CPU and GPU
        int cpu_temp = getTypeTemperature(thermalZones, "cpu-thermal");
        int gpu_temp = getTypeTemperature(thermalZones, "gpu-thermal");

        // Update temperatures with mutex protection
        {
            std::lock_guard<std::mutex> lock(mtx);
            
            // Format CPU temperature
            if (cpu_temp != -1) {
                float temp = (unit == TempUnit::Celsius) ? 
                           static_cast<float>(cpu_temp) : 
                           celsiusToFahrenheit(static_cast<float>(cpu_temp));
                cpuTemp = std::to_string(static_cast<int>(temp)) + 
                         ((unit == TempUnit::Celsius) ? "°C" : "°F");
            } else {
                cpuTemp = "N/A";
            }
            
            // Format GPU temperature
            if (gpu_temp != -1) {
                float temp = (unit == TempUnit::Celsius) ? 
                           static_cast<float>(gpu_temp) : 
                           celsiusToFahrenheit(static_cast<float>(gpu_temp));
                gpuTemp = std::to_string(static_cast<int>(temp)) + 
                         ((unit == TempUnit::Celsius) ? "°C" : "°F");
            } else {
                gpuTemp = "N/A";
            }
        }

        // Sleep for the configured logging interval
        std::this_thread::sleep_for(std::chrono::seconds(loggingInterval));
    }
}

/**
 * Displays real-time progress information and system temperatures
 * Updates the display every second with remaining time and current temperatures
 * 
 * @param duration Total duration of the stress test in seconds
 * @param mode Current test mode (0=CPU, 1=GPU, 2=Both)
 * @param running Atomic flag controlling the progress display
 * @param gpuTemp Current GPU temperature string
 * @param cpuTemp Current CPU temperature string
 * @param mtx Mutex for thread-safe temperature access
 */
void printProgress(int duration, int mode, std::atomic<bool>& running, const std::string& gpuTemp, const std::string& cpuTemp, std::mutex& mtx) {
    std::string modeDescription;
    switch (mode) {
        case 0:
            modeDescription = "CPU Stress Test";
            break;
        case 1:
            modeDescription = "GPU Stress Test";
            break;
        case 2:
            modeDescription = "GPU and CPU Stress Test";
            break;
        default:
            modeDescription = "Unknown Mode";
            break;
    }

    for (int i = 0; i < duration; ++i) {
        if (!running) break;
        {
            std::lock_guard<std::mutex> lock(mtx);
            std::cout << "\r" << GREEN << "Mode: " << RESET << modeDescription 
                      << GREEN << " | Time remaining: " << RESET << (duration - i) << GREEN << " seconds"
                      << " | GPU Temp: " << RESET << gpuTemp 
                      << GREEN << " | CPU Temp: " << RESET << cpuTemp << std::flush;
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    std::cout << std::endl;
    running = false;
}

/**
 * Logs temperature data to a file at regular intervals
 * Creates a log file with timestamp and records temperature data every 10 seconds
 * 
 * @param running Atomic flag controlling the logging loop
 * @param filename Name of the output log file
 * @param mode Current test mode for logging reference
 * @param mtx Mutex for thread-safe temperature access
 */
void logTemperatures(std::atomic<bool>& running, const std::string& filename, 
                    int mode, std::mutex& mtx, int interval_seconds,
                    TempUnit unit = TempUnit::Celsius) {
    // Initial scan of thermal zones
    std::vector<ThermalZone> thermalZones = scanThermalZones();
    
    std::ofstream logFile(filename);
    if (!logFile.is_open()) {
        std::cerr << "Failed to open log file" << std::endl;
        return;
    }

    std::string modeDescription;
    switch (mode) {
        case 0: modeDescription = "CPU Stress Test"; break;
        case 1: modeDescription = "GPU Stress Test"; break;
        case 2: modeDescription = "GPU and CPU Stress Test"; break;
        default: modeDescription = "Unknown Mode"; break;
    }

    auto now = std::chrono::system_clock::now();
    std::time_t now_c = std::chrono::system_clock::to_time_t(now);
    char buf[80];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", std::localtime(&now_c));
    
    // Write header
    logFile << "RB-Load Stress Test Log" << std::endl;
    logFile << "======================" << std::endl;
    logFile << "Mode: " << modeDescription << std::endl;
    logFile << "Start Time: " << buf << std::endl;
    logFile << "Logging Interval: " << interval_seconds << " seconds" << std::endl;
    logFile << "Detected Thermal Zones:" << std::endl;
    for (const auto& zone : thermalZones) {
        logFile << "- " << zone.type << " (" << zone.path << ")" << std::endl;
    }
    logFile << "======================" << std::endl;
    
    // Create CSV header with all thermal zones
    logFile << "Time";
    for (const auto& zone : thermalZones) {
        logFile << "," << zone.type;
    }
    logFile << std::endl;

    while (running) {
        // Use the provided interval_seconds instead of a hardcoded value
        std::this_thread::sleep_for(std::chrono::seconds(interval_seconds));
        now = std::chrono::system_clock::now();
        now_c = std::chrono::system_clock::to_time_t(now);
        std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", std::localtime(&now_c));
        
        // Update temperatures
        updateTemperatures(thermalZones);
        
        std::lock_guard<std::mutex> lock(mtx);
        logFile << buf;
        for (const auto& zone : thermalZones) {
            if (zone.temp != -1) {
                float temp = (unit == TempUnit::Celsius) ? 
                           static_cast<float>(zone.temp) : 
                           celsiusToFahrenheit(static_cast<float>(zone.temp));
                logFile << "," << static_cast<int>(temp) << 
                          ((unit == TempUnit::Celsius) ? "°C" : "°F");
            } else {
                logFile << ",N/A";
            }
        }
        logFile << std::endl;
        logFile.flush();
    }
    
    // Write footer
    logFile << "======================" << std::endl;
    logFile << "Test completed at: " << buf << std::endl;
    logFile.close();
}

/**
 * Performs CPU stress testing using multiple threads
 * Creates one thread per available CPU core and runs intensive calculations
 * 
 * @param duration Duration of the stress test in seconds
 * @param running Atomic flag controlling the stress test
 */
void cpuStressTest(int duration, std::atomic<bool>& running) {
    int num_threads = std::thread::hardware_concurrency();
    std::vector<std::thread> threads;

    for (int t = 0; t < num_threads; ++t) {
        threads.emplace_back([&running]() {
            while (running) {
                double x = 0.0001;
                for (int i = 0; i < 1000000; ++i) {
                    x = x * x - x + 2.0f; // Arbitrary computations
                }
            }
        });
    }

    std::this_thread::sleep_for(std::chrono::seconds(duration));
    running = false;

    for (auto &t : threads) {
        t.join();
    }
}

/**
 * Validates if a string represents a valid integer
 * Handles positive and negative numbers
 * 
 * @param s String to validate
 * @return true if string is a valid integer, false otherwise
 */
bool isInteger(const std::string &s) {
    if (s.empty() || ((!isdigit(s[0])) && (s[0] != '-') && (s[0] != '+'))) return false;
    char *p;
    strtol(s.c_str(), &p, 10);
    return (*p == 0);
}

/**
 * RAII wrapper for GPU memory management.
 * Handles allocation and deallocation of both host and device memory.
 * Ensures proper cleanup of resources even in case of exceptions.
 */
class GPUMemoryManager {
private:
    float* d_data;    // Device (GPU) memory pointer
    float* h_data;    // Host memory pointer
    int N;            // Size of the arrays

public:
    /**
     * Constructor: Allocates host and device memory and initializes data
     * @param size Number of elements to allocate
     * @throws std::runtime_error if GPU memory allocation or copy fails
     */
    GPUMemoryManager(int size) : N(size), d_data(nullptr), h_data(nullptr) {
        h_data = new float[N];
        for (int i = 0; i < N; ++i) {
            h_data[i] = static_cast<float>(i);
        }
        
        cudaError_t err = cudaMalloc(&d_data, N * sizeof(float));
        if (err != cudaSuccess) {
            delete[] h_data;
            throw std::runtime_error(std::string("Failed to allocate GPU memory: ") + cudaGetErrorString(err));
        }

        err = cudaMemcpy(d_data, h_data, N * sizeof(float), cudaMemcpyHostToDevice);
        if (err != cudaSuccess) {
            cudaFree(d_data);
            delete[] h_data;
            throw std::runtime_error(std::string("Failed to copy data to GPU: ") + cudaGetErrorString(err));
        }
    }

    /**
     * Destructor: Ensures proper cleanup of GPU and host memory
     */
    ~GPUMemoryManager() {
        if (d_data) cudaFree(d_data);
        if (h_data) delete[] h_data;
    }

    /**
     * @return Pointer to the device memory for use in CUDA kernels
     */
    float* getDeviceData() const { return d_data; }
};

// Add this function before main():
void printHelp() {
    std::cout << "REBOTNIX RB-LOAD STRESS TOOL" << std::endl;
    std::cout << "WRITTEN BY GARY HILGEMANN FOR REBOTNIX, GERMANY" << std::endl;
    std::cout << "ALL RIGHTS RESERVED 2024-now." << std::endl;
    std::cout << "USE WITH OWN RISK." << std::endl;
    std::cout << std::endl;
    std::cout << "Usage:" << std::endl;
    std::cout << "  rbload -m=[mode] -t=[duration] -stats=[true/false] -o=[output_file] -unit=[C/F]" << std::endl;
    std::cout << std::endl;
    std::cout << "Parameters:" << std::endl;
    std::cout << "  -m=[mode]      : Test mode (Required)" << std::endl;
    std::cout << "                   0 = CPU only" << std::endl;
    std::cout << "                   1 = GPU only" << std::endl;
    std::cout << "                   2 = Both CPU and GPU" << std::endl;
    std::cout << "  -t=[duration]  : Test duration in seconds (Default: 60)" << std::endl;
    std::cout << "  -stats=[bool]  : Enable/disable temperature logging (Default: true)" << std::endl;
    std::cout << "  -o=[filename]  : Output log file name (Default: timestamp.txt)" << std::endl;
    std::cout << "  -unit=[C/F]    : Temperature unit (C=Celsius [default], F=Fahrenheit)" << std::endl;
    std::cout << "  -interval=[seconds] : Temperature logging interval in seconds" << std::endl;
    std::cout << "                       (Default: 5, Min: 1 if test duration < 5s)" << std::endl;
    std::cout << "  -h, --help     : Show this help message" << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  CPU only test for 30 seconds with Celsius:" << std::endl;
    std::cout << "    ./rbload -m=0 -t=30" << std::endl;
    std::cout << std::endl;
    std::cout << "  GPU only test with Fahrenheit temperatures:" << std::endl;
    std::cout << "    ./rbload -m=1 -t=60 -unit=F" << std::endl;
    std::cout << std::endl;
    std::cout << "  Full stress test with custom log file:" << std::endl;
    std::cout << "    ./rbload -m=2 -t=120 -o=stress_test.log" << std::endl;
    std::cout << std::endl;
}

/**
 * Main function - Entry point of the stress test application
 * Parses command line arguments and orchestrates the stress testing
 * 
 * Command line arguments:
 * -m=<mode>     : Test mode (0=CPU, 1=GPU, 2=Both)
 * -t=<duration> : Test duration in seconds
 * -stats=<bool> : Enable/disable temperature logging
 * -o=<filename> : Output log file name
 * -unit=<C/F>   : Temperature unit (C=Celsius [default], F=Fahrenheit)
 * 
 * @return 0 on successful completion, 1 on error
 */
int main(int argc, char *argv[]) {
    // Show help if no arguments or -h/--help is specified
    if (argc == 1 || (argc == 2 && (std::string(argv[1]) == "-h" || std::string(argv[1]) == "--help"))) {
        printHelp();
        return 0;
    }

    int mode = -1;
    int duration = 60;  // Default duration: 60 seconds
    bool enableStats = true;
    std::string outputFile;  // Will be set to timestamp or user value
    TempUnit tempUnit = TempUnit::Celsius;
    int loggingInterval = 5;  // Default interval: 5 seconds
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg.substr(0, 3) == "-m=") {
            mode = std::stoi(arg.substr(3));
        } else if (arg.substr(0, 3) == "-t=") {
            duration = std::stoi(arg.substr(3));
        } else if (arg.substr(0, 7) == "-stats=") {
            enableStats = (arg.substr(7) == "true");
        } else if (arg.substr(0, 3) == "-o=") {
            outputFile = arg.substr(3);
        } else if (arg.substr(0, 6) == "-unit=") {
            tempUnit = (arg.substr(6) == "F") ? TempUnit::Fahrenheit : TempUnit::Celsius;
        } else if (arg.substr(0, 10) == "-interval=") {
            try {
                int interval = std::stoi(arg.substr(10));
                loggingInterval = std::max(1, interval);
                std::cout << "Setting logging interval to " << loggingInterval << " seconds" << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "Invalid interval value. Using default of 5 seconds." << std::endl;
                loggingInterval = 5;
            }
        }
    }

    // Generate timestamp filename if no output file specified
    if (outputFile.empty()) {
        auto now = std::chrono::system_clock::now();
        auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch());
        outputFile = std::to_string(now_ms.count()) + ".txt";
    }

    // Print usage if invalid mode
    if (mode < 0 || mode > 2) {
        std::cout << "Usage: " << argv[0] << " -m=[mode] -t=[duration] -stats=[true/false] -o=[output_file] -unit=[C/F] -interval=[seconds]\n";
        std::cout << "Modes:\n";
        std::cout << "  0: CPU stress test only\n";
        std::cout << "  1: GPU stress test only\n";
        std::cout << "  2: Combined CPU and GPU stress test\n";
        std::cout << "Parameters:\n";
        std::cout << "  -m=[mode]      : Test mode (0=CPU, 1=GPU, 2=Both)\n";
        std::cout << "  -t=[duration]  : Test duration in seconds (default: 60)\n";
        std::cout << "  -stats=[bool]  : Enable/disable temperature logging (default: true)\n";
        std::cout << "  -o=[filename]  : Output log file name (default: temperature_log.txt)\n";
        std::cout << "  -unit=[C/F]    : Temperature unit (C=Celsius [default], F=Fahrenheit)\n";
        std::cout << "  -interval=[sec]: Temperature logging interval in seconds (default: 5, min: 1)\n";
        return 1;
    }

    std::atomic<bool> running(true);
    std::string gpuTemp = "N/A";
    std::string cpuTemp = "N/A";
    std::mutex mtx;

    std::cout << "REBOTNIX RB-LOAD STRESS TOOL" << std::endl;
    std::cout << "WRITTEN BY GARY HILGEMANN FOR REBOTNIX, GERMANY" << std::endl;
    std::cout << "ALL RIGHTS RESERVED 2024-now." << std::endl;
    std::cout << "USE WITH OWN RISK." << std::endl;
    std::cout << std::endl;

    std::cout << "Starting stress test with mode " << mode << " for " << duration << " seconds." << std::endl;
    std::cout << "Temperature unit: " << (tempUnit == TempUnit::Celsius ? "Celsius" : "Fahrenheit") << std::endl;
    std::cout << "Logging interval: " << loggingInterval << " seconds" << std::endl;

    std::thread infoThread(printProgress, duration, mode, std::ref(running), std::ref(gpuTemp), std::ref(cpuTemp), std::ref(mtx));
    std::thread tempThread(monitorTemperatures, std::ref(running), std::ref(gpuTemp), std::ref(cpuTemp), std::ref(mtx), tempUnit);
    std::thread logThread;
    if (enableStats) {
        logThread = std::thread(logTemperatures, std::ref(running), outputFile, 
                               mode, std::ref(mtx), loggingInterval, tempUnit);
    }

    if (mode == 1 || mode == 2) {
        const int N = 1024 * 1024; // Array size in elements (1 million elements)
        const int threadsPerBlock = 256;
        const int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;

        std::unique_ptr<GPUMemoryManager> gpuManager;
        try {
            gpuManager = std::make_unique<GPUMemoryManager>(N);
        } catch (const std::runtime_error& e) {
            std::cerr << e.what() << std::endl;
            return 1;
        }

        auto gpuStressLambda = [=, &running, &gpuManager]() {
            while (running) {
                gpuStressTest<<<blocksPerGrid, threadsPerBlock>>>(gpuManager->getDeviceData(), N);
                cudaDeviceSynchronize();
            }
        };

        std::thread gpuThread(gpuStressLambda);
        if (mode == 2) {
            std::thread cpuThread(cpuStressTest, duration, std::ref(running));
            cpuThread.join();
        }
        gpuThread.join();
    } else if (mode == 0) {
        std::thread cpuThread(cpuStressTest, duration, std::ref(running));
        cpuThread.join();
    }

    infoThread.join();
    running = false;
    tempThread.join();
    if (enableStats && logThread.joinable()) {
        logThread.join();
    }

    std::cout << "Stress test completed." << std::endl;
    return 0;
}