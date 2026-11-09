
Split Gyro Game Controller
A modular, two-handed wireless game controller featuring an FPGA-accelerated motion-processing pipeline, swappable input cartridges and independent sensing in each controller half.
This project is being developed from the ground up as a portfolio piece focused on FPGA design, embedded systems, PCB development and hardware–software integration.
Project Overview
The Split Gyro Game Controller is a Joy-Con-style controller consisting of two independently powered halves. Each half can be used separately or connected to a central grip bridge to form a conventional gamepad.
An FPGA in each half handles time-sensitive sensor acquisition and motion processing in RTL, providing predictable, low-latency operation. An ESP32-S3 manages wireless communication, button scanning and system-level control, and implements HID reporting on the right half for wired operation.
Key features include:
* Independent six-axis motion sensing in both controller halves
* FPGA-based SPI acquisition and sensor fusion
* Wireless communication between controller halves using ESP-NOW
* USB dongle link over ESP-NOW, with BLE as a fallback
* Wired USB-C support when docked
* Swappable joystick and D-pad cartridges, with the stick and D-pad positions interchangeable on the left half
* Five additional user-assignable inputs on each half, reported as keyboard keys so they work without any host software
* A separate profile button, placed near the menu controls and recessed against accidental presses, which selects between the three stored profiles when held with A, B or Y
* Contactless TMR joysticks and Hall-effect triggers
* Automatic dock and cartridge detection
Operating Modes
Undocked Mode
When separated, each controller half operates as an independent handheld input device.
* One controller half is held in each hand
* Each half runs its own FPGA motion-processing pipeline
* Each half maps its own inputs through the active profile and sends a finished chunk to the dongle over ESP-NOW, one hop each
* The dongle holds the report layout and assembles the two chunks into a single Composite HID report. It applies no mapping of its own
* Independent motion sensing supports both left- and right-handed configurations, selected per profile
Docked Mode
The two halves attach to a central grip bridge using rare-earth magnets and pogo-pin contacts.
* Pogo pins establish power and data connections automatically
* A DOCK_DETECT signal switches the firmware into docked mode
* Docking changes nothing about the radio: both halves still send to the dongle unless a cable is attached. No ESP-NOW traffic crosses the dock contacts in either case. The right half's contacts do carry the USB D+/D- pair from the bridge, so when wired the assembled report crosses them as USB; the left half's carry only power and DOCK_DETECT
* The assembled device functions as a conventional gamepad with motion controls
* USB-C carries power and data simultaneously, so the controller charges while in use
* In wired mode the right half enumerates directly as the HID device, using the same descriptor as the dongle
* Wired takes precedence: once USB enumeration completes, the left half sends its chunks to the right half instead of the dongle and the dongle goes quiet, so the host never sees two identical gamepads. The trigger is completed enumeration rather than bus voltage, since a wall charger also supplies VBUS and must not silence the wireless link
* The dongle link remains available for wireless operation
Pairing
The halves and the dongle find each other over ESP-NOW on a fixed channel chosen at build time and shared by all three, selected away from local Wi-Fi traffic. On first boot a device with no stored peer broadcasts, learns the source address from the frame it receives and writes it to flash.

Pairing requires a deliberate gesture at both ends within a short window rather than completing on any received broadcast, and is gated on signal strength so the devices must be physically adjacent. Without those two conditions, two controllers being paired in the same room could learn each other's halves. Re-pairing is initiated by a button combination on the right half; the dongle has no button.

Onboard Profiles
The controller stores three profiles in its own flash. Each holds a button mapping, a sensitivity setting and the user's preferred hand. Profiles are selected on the controller itself using a dedicated modifier button combined with A, B or Y, so switching is invisible to the host and requires no software installed on the machine.

Mapping is applied by each half to its own inputs, not centrally. Both halves send a finished chunk, and the device holding the USB connection assembles them:

    wireless:  left half  ---ESP-NOW--> dongle --> USB --> host
               right half ---ESP-NOW-->

    wired:     left half  ---ESP-NOW--> right half --> USB --> host

The assembling device knows the report layout but applies no mapping of its own, so the profiles never have to exist on it as well. Each half holds its own copy and owns the interpretation of its own inputs.

Every chunk header carries the active profile ID. A report is only assembled when both halves' current chunks carry the same ID; during a profile transition the last consistent pair is re-emitted. That removes the window in which one half has switched and the other has not, with no handshake and no phantom inputs. The same field tells the assembling device which USB interface set the profile calls for, so no separate notification is needed.

The profile-switch combination must use right-half inputs only. This holds in both modes: wirelessly the right half never sees the left half's inputs at all, and wired it receives only chunks that have already been mapped, not raw button states.

One profile may drop the gamepad entirely. Selecting the keyboard-and-mouse profile makes the device re-enumerate declaring only its keyboard and mouse interfaces, with the thumbstick mapped to movement keys and the gyroscope to the mouse. Leaving the gamepad interface present but idle was considered and rejected: games detect that a gamepad interface exists, not that it is reporting. Two descriptor sets are held in firmware, the full one and the keyboard-and-mouse one, and whichever device owns the USB connection re-enumerates - the dongle wirelessly, the right half wired. The cost is roughly a second of disconnection and the host's device-connect sound.

The dongle is never told which profile is active. It reads the profile ID already present in every chunk header, and looks it up in a static table mapping profile to interface set, held alongside the descriptors so the three builds cannot disagree about it. That avoids a second message type and the ordering problem a push would create between the notification and the chunks changing; if a chunk is missed the next one corrects it, so the dongle can only ever be one chunk behind, well under a millisecond.

Handedness is a per-profile setting rather than a mode. Undocked, it selects which half's gyroscope drives aiming, since each hand moves independently. Docked, the halves are rigidly joined so both gyroscopes observe the same motion, and the preferred half's is used. Gyroscope data is always reported when docked; whether a game acts on it is that game's setting, as it is on a DualSense.

Host Connection
The controller reaches the host through a small USB dongle rather than connecting over Bluetooth directly.

    left half  --ESP-NOW--> dongle --USB HID--> host
    right half --ESP-NOW-->

The dongle is an ESP32-S3 that receives a mapped chunk from each half, assembles them into one report and presents itself to the host as a Composite HID device. It carries the report layout, the descriptor and the device identity; the mapping and profile logic live on the halves. Three reasons this is the primary path rather than BLE:

* Latency. BLE HID typically lands around 7.5-15 ms. The dongle path is bounded below by USB itself: full-speed HID polls at a 1 ms minimum interval, and the ESP32-S3 is a full-speed device, so sub-millisecond reporting is not reachable and is not claimed. Estimated end-to-end figures, to be replaced by measurement, are 2-6 ms wirelessly for either half and 1-3 ms wired.
* Separation of concerns. Each half maps its own inputs through the active profile; the device holding the USB connection assembles the two chunks using the report layout, and applies no mapping itself. Wired and wireless therefore behave identically by construction rather than by keeping two implementations in step.
* Debuggability. USB enumeration fails visibly and immediately, and the dongle is a desk-bound board with no battery or wireless link in the way of inspecting it.

The host sees a USB HID device, so Steam Input recognises it the same way it recognises any wired controller - from the vendor and product ID and the descriptor.

One limitation is worth stating plainly: games that read XInput exclusively will not see a generic HID gamepad, because XInput only enumerates devices presenting as Xbox controllers. Anything launched through Steam is covered, since Steam Input translates for them, and outside Steam the keyboard-and-mouse profile covers most of the rest, since the great majority of PC titles accept keyboard and mouse. The residue is the small number of PC games that are controller-only and XInput-only; those would need a translation layer such as a virtual controller driver, or the device to spoof an Xbox identity, which is explicitly not the intent here. Note that SDL's controller GUID is understood to encode the bus type, so the USB and BLE paths may need separate mapping entries; this needs verifying before the mapping is submitted.

BLE remains on the roadmap as a fallback for use without the dongle. Note the ESP32-S3 supports Bluetooth Low Energy only, not Bluetooth Classic.

Power and Connections
Three USB-C ports: one on each half and one on the grip bridge.

* The left half's port carries data. It is that half's only wired path, needed for first flash and for recovery.
* The right half's port is charge-only - VBUS, ground and the CC pull-downs, with no data pair. Its ESP32's USB peripheral is fixed to GPIO19 and GPIO20 and already routes to the bridge, and one USB peripheral cannot serve two receptacles. The right half is flashed through the bridge instead.
* The bridge's port is the wired HID path. It carries 5 V, ground, DOCK_DETECT and the USB data pair to the right half.

All three ports need 5.1 k CC pull-down resistors, or a C-to-C cable will not supply 5 V at all.

The halves attach to the bridge magnetically, with spring contacts for the electrical connection. Three details matter for a connection that is hot-plugged and carries power: ground contacts are staggered longer so they mate first and break last, 5 V and ground are doubled for lower resistance and redundancy, and the magnets are polarity-keyed so a half cannot be docked on the wrong side.

One risk is recorded rather than solved: the USB data pair crosses the dock's spring contacts, which is a mechanical and hot-pluggable junction on the lowest-latency path. Full-speed USB is comparatively tolerant of this, but it will be bench-tested across the contacts before the boards are laid out.

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
      ↓ ESP-NOW
USB dongle, or the right half when wired
Input-Cartridge Path
Cartridge hardware ID
      ↓
FPGA detection logic
      ↓
Input routing
      └── ADC path for analogue controls
          (digital inputs are read by the ESP32, not the FPGA)
Hardware Stack
Each controller half uses the following primary components:
Component	Part	Purpose
FPGA	Lattice iCE40UP5K, SG48 package	SPI control, motion processing, sensor fusion and cartridge routing
Microcontroller	Espressif ESP32-S3-MINI-1-N8	ESP-NOW, button scanning, system management, and USB HID on the right half when wired
IMU	TDK InvenSense ICM-45686	Six-axis gyroscope and accelerometer data over SPI
Joystick	K-Silver JS13 Pro Plus TMR	Contactless analogue input with improved resistance to stick drift
ADC	MCP3204 or MCP3208 (SPI, 12-bit)	Digitises the joystick axes from both cartridge receptacles. The iCE40UP5K has no on-chip ADC, so an external converter is required. The left half needs four channels, two per receptacle, with two live at a time depending on which receptacle holds the stick. The right half has a single receptacle and needs two. Prototyped with the same 12-bit part rather than the 10-bit MCP3008, so the framing validated is the framing that ships.
Trigger sensor	TI DRV5055A1QLPG	Contactless Hall-effect trigger-position sensing, read directly by the ESP32 on an ADC1 pin. ADC2 shares hardware with the WiFi radio that ESP-NOW uses, so readings there would be unreliable whenever the link is active
Buttons	Kailh mouse switches	Replaceable mechanical button inputs
Charger	To be selected (power-path, single cell)	One per half. A power-path part is required rather than a plain charger: its separate system output runs the load from USB when present and from the battery otherwise, so charge termination is not confused by load current, the battery does not cycle while plugged in, and a flat battery still lets the device run. Each half has two 5 V sources - its own USB-C port and the dock contacts - which must tolerate being live together without back-feeding, either through a dual-input part or by ORing them with ideal diodes. The charge current target has not been set either, and it drives both the part choice and the thermal design
Regulators	To be selected	Each half needs both a 1.2 V core rail (VCC and VCC_PLL) and 3.3 V VCCIO for the FPGA. Confirmed against the UltraPlus breakout board, which carries discrete 3.3 V and 1.2 V supplies. iCE40 configuration is sensitive to power sequencing, so the ESP32 must not begin clocking a bitstream before the FPGA's rails are stable
Oscillator	To be selected	The FPGA needs an external oscillator. The UP5K's internal oscillator is not accurate enough for UART, which tolerates only a couple of percent of baud error, and the breakout board's 12 MHz part is not inherited by a custom design

Battery	Single-cell LiPo, capacity not yet fixed	Independent power supply with JST-PH 2.0 mm connection. 2000 mAh is a starting point rather than a decision: the cell dominates the weight budget at roughly 35-40 g, so a smaller one is on the table, and the capacity that makes sense depends on measured current draw
FPGA Design
The iCE40UP5K performs two concurrent RTL functions.
1. Motion-Processing Pipeline
The FPGA communicates directly with the ICM-45686 over SPI, acquires gyroscope and accelerometer measurements and processes them through a complementary filter.
The resulting orientation and motion data are transmitted to the ESP32-S3 over UART.
Planned RTL modules include:
* SPI master, instantiated twice on separate buses - one for the IMU, one for the ADC - so ADC reads never contend with IMU bursts
* IMU register controller
* ADC controller, handling the MCP320x conversion framing
* Gyroscope bias calibration with stillness detection
* CORDIC arctangent for accelerometer tilt
* Fixed-point complementary filter
* Cartridge identification with debounce
* UART transmitter and sensor packet framing, running at 1 Mbaud
2. Cartridge Detection and Input Routing
Each cartridge exposes a hardware-identification signal. The FPGA reads this signal and selects the appropriate input path:
* Debounced identification of the installed cartridge, including hot-swap detection
* Sampling the external ADC on whichever receptacle holds the thumbstick, since either can
* Forwarding the cartridge IDs to the ESP32 in the sensor packet's status byte, two bits each. The left half reports two, the right half one with the second field reading none, so a single packet format serves both

Digital button inputs are deliberately not routed through the FPGA. A button press is a human-timescale event, so the FPGA's determinism buys nothing, and routing it through the FPGA would add a UART hop before the signal reaches the radio. The ESP32-S3 owns the radio link, so it reads button GPIO directly and debounces in firmware. This gives the shortest possible path from press to transmitted report, and frees FPGA pins on the 48-pin package for the sensor pipeline. The FPGA still owns cartridge identification, since the ID determines routing for the analogue path.
Modular Cartridge System
The left half has two receptacles and the right half one. Either of the left half's receptacles can take a thumbstick or a D-pad, which is what allows their positions to be swapped between the PlayStation and Xbox layouts. The right half's receptacle takes a thumbstick only; its ABXY buttons are fixed to the motherboard and wired directly to the ESP32, since nothing about that layout varies between the two conventions.

All three receptacles share an identical connector pinout, including the four digital lines the right half's never uses, which are left unconnected on that board. This keeps a joystick cartridge a single part number across both halves, for spares and for resale.

The controller supports two swappable input cartridges:
* TMR joystick cartridge
* D-pad cartridge
Each cartridge uses:
* A twist-lock ring for retention, with a magnet to seat and align the cartridge. The magnet only has to pull it into place rather than hold it against gameplay forces, so it can be weaker than a magnet-only design would need - which matters next to the TMR joystick, since that senses magnetic fields
* Two digital hardware-identification pins, pulled high on the motherboard and grounded in a pattern by the cartridge. Three codes are in use - none, thumbstick and D-pad - leaving the fourth spare. Plain GPIO is used rather than a resistor-coded analogue ID because the FPGA has no on-chip ADC and every channel of the external one is committed to the stick axes
The system is inspired by replaceable controller modules such as those used by the DualSense Edge, while extending the concept to multiple input types.
PCB Ecosystem
The complete system is planned around six custom PCBs.
Board	Main Components and Functions
Left motherboard	FPGA, ESP32-S3, IMU, power-path charger, dock contacts and two cartridge receptacles
Right motherboard	FPGA, ESP32-S3, IMU, power-path charger, dock contacts, fixed ABXY buttons and one cartridge receptacle
Joystick cartridge	K-Silver JS13 TMR joystick, connector and joystick hardware ID
D-pad cartridge	Digital directional inputs, connector and D-pad hardware ID
Grip bridge PCB	USB-C interface, pogo-pin arrays, magnets, DOCK_DETECT, and routing of the USB data pair to the right half
Dongle	ESP32-S3-MINI-1-N8, USB-A plug and status LED
PC Integration
Wirelessly, the dongle assembles both halves' chunks and is what the host enumerates. Wired, the right half does the assembling and enumerates directly.
Planned PC-side functionality includes:
* Composite HID operation over the USB dongle, with BLE as a fallback
* Simultaneous gamepad and mouse input
* Gyroscope-based mouse or camera control
* Steam Input compatibility
* Per-game input profiles, in addition to the three stored on the controller itself
* Adjustable motion-sensitivity curves
* Controller calibration
* Firmware updates through a custom configuration application

Device Identity
The device presents its own HID vendor and product ID - carried by the dongle when wireless, and by the right half when wired - rather than spoofing an existing commercial gamepad. A unique identity is required for Steam Input to apply the correct controller profile, for the operating system to bind the right driver, and for the configuration application to reliably target this device. The planned route is a product ID issued free under Espressif's vendor ID 0x303A, which carries no open-source condition, with a corresponding SDL game-controller mapping entry so the device is recognised correctly without per-user configuration. Development uses the default TinyUSB product ID under that vendor; a dedicated one will be applied for before the Steam Input validation work, so the mapping is tested against the identity that ships.

Software and Development Tools
Tool	Purpose
VS Code and OSS CAD Suite	Verilog development, synthesis, placement and routing
VaporView	RTL waveform inspection and simulation
Zephyr RTOS and west	ESP32-S3 firmware for both halves and the dongle
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
│   ├── spi_master/           # Generic SPI master, drives the IMU and the ADC
│   ├── imu_controller/       # ICM-45686 configuration and burst reads
│   ├── adc_controller/       # MCP320x framing for the joystick axes
│   ├── complementary_filter/ # Gyro bias, CORDIC and sensor fusion
│   ├── cartridge_id/         # Cartridge identification with debounce
│   ├── uart_tx_rx/           # UART and sensor packet framing
│   └── top/                  # Board top level, pin constraints, build script
│       (testbenches live alongside their module in each folder)
├── firmware/
│   ├── common/               # Shared HID descriptor, device identity, packet format
│   ├── esp32-right/          # Primary half: aggregation, wired USB HID
│   ├── esp32-left/           # Secondary half: acquisition and ESP-NOW
│   └── esp32-dongle/         # Receives ESP-NOW, presents USB HID to the host
├── pcb/                      # KiCad schematics and PCB layouts
├── mechanical/                # Fusion 360 models and enclosure files
└── docs/                      # Project documentation and datasheets

Validation Plan
Each subsystem will be prototyped and tested before the custom PCBs are designed.
1. FPGA-to-IMU SPI communication
2. Complementary filter implementation in RTL
3. FPGA-to-ESP32 UART communication at 1 Mbaud. The 21-byte packet takes 1.82 ms at 115200, which rivals the radio hop and would dominate the latency budget; 1 Mbaud divides exactly into the 12 MHz clock, so there is no baud error to tolerate
4. USB HID dongle enumeration and reporting (BLE Composite HID deferred to a fallback)
5. Wired docked HID from the right half, including handover away from the dongle
6. ESP-NOW from each half to the dongle, the primary input path
7. The right-to-left control channel carrying the active profile and the wired/wireless mode. The dongle is not a recipient: it infers the profile from the chunk headers
8. Joystick ADC acquisition, read by the FPGA over SPI. Prototype with an MCP3204 or MCP3208 rather than the 10-bit MCP3008, so the 12-bit framing being validated is the framing that ships
9. Hall-effect trigger sensing
10. Digital button scanning
11. Dock-contact charging, prototyped with a TP4056. Note this proves the contact handoff only - the TP4056 is a plain charger and cannot validate power-path behaviour, which needs testing separately once that part is chosen
12. Cartridge-detection logic using jumper-wire hardware IDs
13. FPGA configuration by the ESP32, streaming the bitstream in at boot and confirming CDONE, including rail-stability sequencing and the failure path where CDONE never asserts
14. Profile storage in flash, switching by modifier combination, survival across power loss, and no leakage of the A/B/Y press while the modifier is held
15. Pairing, including the both-ends gesture, the proximity gate, and re-pairing
16. The keyboard-and-mouse profile, including re-enumeration and holding wired precedence across it
17. Flashing routes for both halves: the left half through its own USB-C port, the right half through the bridge. The two differ, and neither is exercised until PCB bring-up unless tested deliberately
Where possible, RTL modules will be verified through simulation before hardware testing.
Project Roadmap
* Validate individual subsystems on breadboard
* Develop and simulate the SPI and UART RTL modules
* Implement the fixed-point complementary filter
* Develop cartridge-detection and input-routing logic
* Implement ESP-NOW and USB HID dongle firmware
* Integrate both controller halves
* Design and review all six PCBs
* Fabricate and assemble the first PCB revision
* Develop the enclosure and cartridge mechanism
* Perform end-to-end latency and reliability testing
* Develop the PC configuration application
* Document final performance and design results
Licence
This repository is published for reading rather than reuse. No licence is granted, which under default copyright means the contents are viewable but not licensed for copying, modification or redistribution. That is deliberate rather than an omission.

Current Status
The project is currently in the breadboard-validation and architecture-development phase. Initial work is focused on verifying the communication interfaces, FPGA sensor pipeline and wireless controller architecture before beginning the first custom PCB revision.
