
Split Gyro Game Controller
A modular, two-handed wireless game controller featuring an FPGA-accelerated motion-processing pipeline, swappable input cartridges and independent sensing in each controller half.
This project is being developed from the ground up as a portfolio piece focused on FPGA design, embedded systems, PCB development and hardware–software integration.
Project Overview
The Split Gyro Game Controller is a Joy-Con-style controller consisting of two independently powered halves. Each half can be used separately or connected to a central grip bridge to form a conventional gamepad.
An FPGA in each half handles time-sensitive sensor acquisition and motion processing in RTL, providing predictable, low-latency operation. An ESP32-S3 manages wireless communication, HID reporting, button scanning and system-level control.
Key features include:
* Independent six-axis motion sensing in both controller halves
* FPGA-based SPI acquisition and sensor fusion
* Wireless communication between controller halves using ESP-NOW
* BLE Composite HID connectivity
* Wired USB-C support when docked
* Swappable joystick, D-pad and face-button cartridges
* Contactless TMR joysticks and Hall-effect triggers
* Automatic dock and cartridge detection
Operating Modes
Undocked Mode
When separated, each controller half operates as an independent handheld input device.
* One controller half is held in each hand
* Each half runs its own FPGA motion-processing pipeline
* The left half transmits its input data to the right half using ESP-NOW
* The right half combines both input streams and connects to the PC
* The controller appears as a single BLE Composite HID device
* Independent motion sensing supports both left- and right-handed configurations
Docked Mode
The two halves attach to a central grip bridge using rare-earth magnets and pogo-pin contacts.
* Pogo pins establish power and data connections automatically
* * A DOCK_DETECT signal switches the firmware into docked mode
* The assembled device functions as a conventional gamepad with motion controls
* USB-C provides a lower-latency wired connection and charges both batteries
* BLE remains available for wireless operation
System Architecture
Each controller half contains an FPGA, ESP32-S3, IMU, battery-management circuitry and a modular input-cartridge interface.
Motion-Processing Path
ICM-45686 IMU
      ↓ SPI
Lattice iCE40UP5K FPGA
      ↓ Sensor fusion
Filtered motion data
      ↓ UART
ESP32-S3
      ↓ BLE HID / ESP-NOW
PC or opposite controller half
Input-Cartridge Path
Cartridge hardware ID
      ↓
FPGA detection logic
      ↓
Input routing
      ├── ADC path for analogue controls
      └── GPIO path for digital controls
Hardware Stack
Each controller half uses the following primary components:
Component	Part	Purpose
FPGA	Lattice iCE40UP5K, SG48 package	SPI control, motion processing, sensor fusion and cartridge routing
Microcontroller	Espressif ESP32-S3-MINI	BLE HID, ESP-NOW, button scanning and system management
IMU	TDK InvenSense ICM-45686	Six-axis gyroscope and accelerometer data over SPI
Joystick	K-Silver JS13 Pro Plus TMR	Contactless analogue input with improved resistance to stick drift
Trigger sensor	TI DRV5055A1QLPG	Contactless Hall-effect trigger-position sensing
Buttons	Kailh mouse switches	Replaceable mechanical button inputs
Charging IC	TI BQ24040DSQR	Single-cell LiPo battery charging
Battery	2000 mAh LiPo	Independent power supply with JST-PH 2.0 mm connection
FPGA Design
The iCE40UP5K performs two concurrent RTL functions.
1. Motion-Processing Pipeline
The FPGA communicates directly with the ICM-45686 over SPI, acquires gyroscope and accelerometer measurements and processes them through a complementary filter.
The resulting orientation and motion data are transmitted to the ESP32-S3 over UART.
Planned RTL modules include:
* SPI master
* IMU register controller
* Sensor-data parser
* Fixed-point complementary filter
* UART transmitter
* Timing and control logic
2. Cartridge Detection and Input Routing
Each cartridge exposes a hardware-identification signal. The FPGA reads this signal and selects the appropriate input path:
* Analogue pipeline for joystick cartridges
* Cartridge-specific input mapping
This allows the controller to identify a newly installed cartridge and reconfigure its input routing automatically.

Digital button inputs are deliberately not routed through the FPGA. A button press is a human-timescale event, so the FPGA's determinism buys nothing, and routing it through the FPGA would add a UART hop before the signal reaches the radio. The ESP32-S3 owns the BLE link, so it reads button GPIO directly and debounces in firmware. This gives the shortest possible path from press to transmitted report, and frees FPGA pins on the 48-pin package for the sensor pipeline. The FPGA still owns cartridge identification, since the ID determines routing for the analogue path.
Modular Cartridge System
The controller supports three swappable input cartridges:
* TMR joystick cartridge
* D-pad cartridge
* ABXY face-button cartridge
Each cartridge uses:
* A USB-C-style connector for electrical contact
* A twist-lock bayonet mechanism for mechanical retention
* A hardware-identification signal for automatic detection
The system is inspired by replaceable controller modules such as those used by the DualSense Edge, while extending the concept to multiple input types.
PCB Ecosystem
The complete system is planned around six custom PCBs.
Board	Main Components and Functions
Left motherboard	FPGA, ESP32-S3, IMU, charging circuit, pogo contacts and cartridge receptacle
Right motherboard	FPGA, ESP32-S3, IMU, charging circuit, pogo contacts and cartridge receptacle
Joystick cartridge	K-Silver JS13 TMR joystick, connector and joystick hardware ID
D-pad cartridge	Digital directional inputs, connector and D-pad hardware ID
Button cartridge	ABXY inputs, connector and button-cartridge hardware ID
Grip bridge PCB	USB-C interface, pogo-pin arrays, magnets and DOCK_DETECT connection
PC Integration
The right controller half acts as the primary host interface and combines input data from both halves.
Planned PC-side functionality includes:
* BLE Composite HID operation
* Simultaneous gamepad and mouse input
* Gyroscope-based mouse or camera control
* Steam Input compatibility
* Per-game input profiles
* Adjustable motion-sensitivity curves
* Controller calibration
* Firmware updates through a custom configuration application

Device Identity
The controller presents its own USB/BLE HID vendor and product ID rather than spoofing an existing commercial gamepad. A unique identity is required for Steam Input to apply the correct controller profile, for the operating system to bind the right driver, and for the configuration application to reliably target this device. The planned route is a free product ID issued under the shared open-source vendor ID 0x1209 via pid.codes, with a corresponding SDL game-controller mapping entry so the device is recognised correctly without per-user configuration.

Software and Development Tools
Tool	Purpose
VS Code and OSS CAD Suite	Verilog development, synthesis, placement and routing
VaporView	RTL waveform inspection and simulation
PlatformIO	ESP32-S3 firmware development
KiCad	Schematic capture and PCB layout
Fusion 360	Enclosure and cartridge-mechanism design
Git and GitHub	Version control, documentation and project history
Fabrication Plan
* Primary PCB manufacturer: JLCPCB
* Alternative manufacturer: PCBWay
* Assembly: JLCPCB PCBA using LCSC-sourced components where available
* PCB construction: Standard four-layer stack-up
* Minimum trace clearance: 0.15 mm
* Minimum via size: 0.20 mm drill / 0.45 mm diameter
All PCB constraints will be reviewed against the selected manufacturer’s current capabilities before fabrication.
Repository Structure
splitGyroController/
├── fpga/
│   ├── spi_master/           # SPI master for the ICM-45686
│   ├── uart_tx_rx/           # FPGA-to-ESP32 UART interface
│   ├── complementary_filter/ # Fixed-point complementary filter
│   └── cartridge_id/         # Cartridge identification and routing
│       (testbenches live alongside their module in each folder)
├── firmware/
│   ├── esp32-right/          # Primary-controller firmware
│   └── esp32-left/           # Secondary-controller firmware
├── pcb/                      # KiCad schematics and PCB layouts
├── mechanical/                # Fusion 360 models and enclosure files
└── docs/                      # Project documentation and datasheets

Validation Plan
Each subsystem will be prototyped and tested before the custom PCBs are designed.
1. FPGA-to-IMU SPI communication
2. Complementary filter implementation in RTL
3. FPGA-to-ESP32 UART communication
4. ESP32 BLE Composite HID connection
5. ESP-NOW communication between controller halves
6. Joystick ADC acquisition using a KY-023 and MCP3008
7. Hall-effect trigger sensing
8. Digital button scanning
9. Pogo-pin charging using a TP4056 prototype circuit
10. Cartridge-detection logic using jumper-wire hardware IDs
Where possible, RTL modules will be verified through simulation before hardware testing.
Project Roadmap
* Validate individual subsystems on breadboard
* Develop and simulate the SPI and UART RTL modules
* Implement the fixed-point complementary filter
* Develop cartridge-detection and input-routing logic
* Implement BLE HID and ESP-NOW firmware
* Integrate both controller halves
* Design and review all six PCBs
* Fabricate and assemble the first PCB revision
* Develop the enclosure and cartridge mechanism
* Perform end-to-end latency and reliability testing
* Develop the PC configuration application
* Document final performance and design results
Current Status
The project is currently in the breadboard-validation and architecture-development phase. Initial work is focused on verifying the communication interfaces, FPGA sensor pipeline and wireless controller architecture before beginning the first custom PCB revision.
