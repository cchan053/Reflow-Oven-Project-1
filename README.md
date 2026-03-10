# Reflow Oven Controller

A microcontroller-based reflow oven controller that executes a full multi-stage soldering profile for PCB assembly. Built on the CV-8052 / DE10-Lite platform in Assembly.

---

## What It Does

Reflow soldering is the standard method for attaching surface-mount components to a PCB. This controller turns a standard 1500 W toaster oven into a precision soldering tool by automatically managing the oven's temperature through four stages:

| Stage | Description |
|-------|-------------|
| **Preheat** | Ramps temperature up gradually to avoid thermal shock |
| **Soak** | Holds temperature steady to activate flux and stabilize the board |
| **Reflow** | Peaks above solder liquidus point to melt and bond solder paste |
| **Cool** | Allows controlled cooldown to form strong solder joints |

---

## Features

- **±3 °C accuracy** (25–240 °C) via K-type thermocouple with cold-junction compensation, calibrated against a lab multimeter
- **PWM power control** of a 1500 W toaster oven through a solid-state relay
- **Fault detection** — aborts the profile automatically if minimum temperature rise is not detected within 60 seconds
- **Embedded UI** — LCD display + large temperature readout for monitoring; editable soak and reflow parameters
- **1 Hz serial telemetry** streamed over UART for real-time plotting and verification in Python

---

## Built With

- **Language:** Assembly (8051 instruction set)
- **Microcontroller:** CV-8052 / DE10-Lite FPGA board
- **Sensing:** K-type thermocouple with cold-junction compensation front-end
- **Actuation:** Solid-state relay (SSR) for mains power switching
- **Interface:** LCD display, 7-segment temperature display
- **Verification:** Python serial app for live telemetry plotting

---

## Hardware Setup

```
[Toaster Oven] ←── [Solid-State Relay] ←── [DE10-Lite / CV-8052]
                                                    │
                                             [K-Type Thermocouple]
                                                    │
                                             [Cold-Junction Comp.]
                                                    │
                                            [LCD + Temp Display]
                                                    │
                                            [UART → PC / Python]
```

---

## How to Run

1. Flash the Assembly binary onto the CV-8052 via the DE10-Lite
2. Connect the K-type thermocouple to the front-end circuit
3. Wire the solid-state relay between the microcontroller and the oven's mains supply (**ensure proper electrical safety precautions**)
4. Power on — the LCD will display current temperature and active stage
5. Adjust soak/reflow target temperatures using the onboard UI controls
6. Optionally, open the Python serial script to monitor live telemetry and plot the temperature curve

---

## Results

- Successfully soldered SMD components onto test PCBs with clean, shiny joints
- Temperature profile tracked within ±3 °C of target across the full 25–240 °C range
- Fault detection correctly aborted test runs when the oven door was left open

---

## Safety Note

This project interfaces with mains voltage (120 V AC). All high-voltage wiring was completed following proper electrical safety procedures. Do not replicate without appropriate knowledge and precautions.

---

## What I Learned

- Practical application of Circuit Analysis for sensor interfacing and signal conditioning
- Embedded UI design under memory and I/O constraints
- Real-world calibration and validation against lab equipment
- Safety-critical fault logic in an embedded system with physical consequences
- That hardware components break all the time!! If the project is not working, check all hardware components!!
