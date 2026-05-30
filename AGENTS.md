Project handoff: Raspberry Pi Stratux-based “toy TCAS / avionics display” project

Context:
I am building a Raspberry Pi-based aviation hobby project around Stratux. This is NOT intended to be certified avionics or real TCAS. “TCAS” is just my internal project codename. The real intent is a fun situational-awareness / toy avionics display and audio-callout system using Stratux ADS-B data, GPS, barometric sensor data, and possibly buttons/speakers/display.

the agent shall feel free to update this file based on newest information and codebase. if the user rolled back the code the agent shall also update this file to keep a record of the current status of the project

Current hardware/setup:
- Raspberry Pi 4B running a Stratux SD card image.
- Stratux image is already burned to a large SD card and boots successfully.
- I can connect to Stratux over Wi-Fi.
- I can SSH into the Pi as user `pi`.
- Stratux is running mostly headless, no GUI Linux desktop by default.
- The Raspberry Pi 4B has micro-HDMI output available, and I may connect it to a portable power bank/display with a built-in 1080p screen.
- The Pi 4B has built-in Bluetooth 5.0, so Bluetooth speaker output is possible, but USB/wired audio may be more reliable.

GPIO/pin scan from Stratux:
- Scanned output is stored at local SSHFS path `~/stratux_pi/pin.txt`; test script is `~/stratux_pi/pintest.sh`.
- Literal local `~/playground/pintest.sh` and `~/playground/pin.txt` were not present; the active mounted Pi playground is `~/stratux_pi`.
- `pintest.sh` checks GPIO modes, kernel GPIO consumers, I2C devices, boot pin overlays/config, serial/SPI devices, and relevant Stratux/Argon services.
- I2C bus 1 is enabled at 400 kHz:
  - `/dev/i2c-1` exists.
  - GPIO2/GPIO3 are configured as SDA1/SCL1.
  - `i2cdetect -y 1` saw a device at `0x1a`.
  - No BMP581-like address (`0x46`/`0x47`) was present in this scan.
  - BMP581 on Qwiic/I2C should not conflict with `0x1a`.
- SPI is enabled:
  - `/dev/spidev0.0` and `/dev/spidev0.1` exist.
  - GPIO7/GPIO8 are used as SPI0 chip selects.
  - GPIO9/GPIO10/GPIO11 are in SPI0 alternate functions.
- UART is enabled:
  - `enable_uart=1`.
  - `/dev/ttyS0` exists.
  - GPIO14/GPIO15 are configured as TXD1/RXD1, so avoid them for buttons unless serial use is intentionally changed.
- Boot config includes `dtoverlay=sc16is752-i2c,int_pin=4,addr=0x4d,xtal=1843900`, but the scan only showed I2C `0x1a`, not `0x4d`; treat the `0x4d` overlay/device as something to verify before relying on it.
- `gpioinfo` showed GPIO4 consumed by `argon`; avoid GPIO4 for project buttons unless Argon One behavior is intentionally disabled/changed.
- `gpioinfo` showed GPIO42 consumed by the ACT LED; not a normal project GPIO.
- Candidate free header GPIOs for simple buttons, subject to wiring/pull-up choices: GPIO5, GPIO6, GPIO12, GPIO13, GPIO16, GPIO17, GPIO19, GPIO20, GPIO21, GPIO22, GPIO23, GPIO24, GPIO25, GPIO26, GPIO27.
- Avoid or be cautious with GPIO0/GPIO1 ID pins, GPIO2/GPIO3 I2C, GPIO7-GPIO11 SPI, GPIO14/GPIO15 UART, GPIO18 PWM, and GPIO4 Argon.
- Tentative 4x4 membrane matrix keypad pins:
  - Physical pins: 29, 31, 35, 37, 32, 36, 38, 40.
  - BCM GPIO mapping: GPIO5, GPIO6, GPIO19, GPIO26, GPIO12, GPIO16, GPIO20, GPIO21.
  - These were free in the pin scan; GPIO12/GPIO19/GPIO20/GPIO21 have PWM/PCM alternate labels on pinout diagrams but were plain inputs in the scan.
  - Not connected yet; ignore keypad/touchpad work until I explicitly return to it.
- Services from scan:
  - `stratux.service` active/running.
  - `stratux_fancontrol.service` active/running.
  - `argononed.service` active/running.

Stratux status:
- Stratux boots and creates/uses its Wi-Fi network.
- Web dashboard is accessible at the Stratux IP, likely `192.168.10.1`.
- Earlier dashboard showed live 1090ES ADS-B messages, so 1090 reception works.
- UAT/weather was showing zero earlier, so 978 MHz FIS-B weather may not yet be received/configured/available.
- I may have two SDR devices connected, but I need to verify 978 UAT assignment/configuration in Stratux settings.
- ADS-B weather/METAR comes from 978 MHz UAT/FIS-B, not 1090ES.
- Weather may not show indoors or on the ground unless the receiver can hear ADS-B ground stations and UAT broadcasts.

Local development workflow:
- I want to use Codex/VS Code from my local computer, because Stratux itself may not have internet access.
- Codex should run on my laptop/desktop with internet, while code is synced or mounted to the Pi.
- Options discussed:
  1. VS Code Remote SSH: easy, but needs VS Code Server installed on the Pi, which runs into overlay space limits.
  2. SSHFS-Win on Windows: mount Pi directory as a drive, then use local VS Code/Codex.
  3. VS Code SFTP extension: keep code local and upload-on-save to Pi.
- Issue found:
  Running `bash` from PowerShell while current directory is `X:\` gives:
  `wsl: Failed to translate 'X:\'`
  because WSL cannot translate the Windows SSHFS drive.
- Workaround:
  - Use `code X:\` from Windows directly, or
  - Launch WSL from `C:\` or `wsl ~`, and mount via Linux `sshfs` inside WSL separately.
- Current Ubuntu SSHFS workflow:
  - I mounted the Stratux Pi playground directory from Ubuntu with:
    `sshfs pi@192.168.50.42:/rwbase/playground ~/stratux_pi -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3`
  - Current Pi SSH/IP for this workflow: `pi@192.168.50.42`.
  - Remote writable project area: `/rwbase/playground`.
  - Local Ubuntu mountpoint: `~/stratux_pi`.

Current local repo/code state:
- Scanned/updated by Codex on 2026-05-29.
- Repository is currently small and Python-only:
  - `README.md`: short project description.
  - `code/helper/traffic_helper.py`: standard-library Stratux `/traffic` WebSocket client, normalizes aircraft updates, sorts nearest first, optional raw updates.
  - `code/helper/gps_helper.py`: tries gpsd first, then falls back to Stratux `/getSituation`; normalizes fix, GPS track, and groundspeed.
  - `code/helper/metar_helper.py`: standard-library Stratux `/weather` WebSocket client, extracts METAR/SPECI messages, parses altimeter setting and rough VFR/MVFR/IFR/LIFR category.
  - `code/__init__.py` and `code/helper/__init__.py`: package markers only.
  - `code/helper/display_helper.py`: pygame helper with `draw_circle_demo()` and a CLI for drawing a simple circle on the display. It first tries a real SDL/pygame display, then can fall back to rendering with pygame into a surface and writing the pixels directly to `/dev/fb0`.
  - `code/helper/audio_helper.py`: pygame mixer helper that plays the default `audio/airbus_retard_retard.wav` callout.
  - `audio/airbus_retard_retard.wav`: first cockpit meme/test callout audio clip.
  - `audio/SOURCES.md`: source and licensing notes for audio assets.
  - The previous `scripts/` setup helpers were intentionally removed by the user on 2026-05-29. Do not recreate them unless explicitly requested.
- There is not yet a main runnable display/audio app, packaging config, dependency file, or automated test suite.
- The helper modules intentionally avoid third-party dependencies so they can run on a constrained Stratux install.
- `traffic_helper.py` and `metar_helper.py` currently each include a small local WebSocket reader; consider sharing it later if this grows.
- Verification from scan: `python3 -m compileall -q code` passes.
- Git status from scan: tracked scripts are deleted in the local workspace, and `AGENTS.md`/`README.md` have been updated to reflect that current state.

Desired project functions:
1. Traffic display / toy TCAS
   - Read live traffic from Stratux.
   - Display nearby aircraft on HDMI screen.
   - Highlight surrounding traffic.
   - Show relative distance, bearing, altitude difference, climb/descent if available.
   - Threat classification based on range, relative altitude, closure rate.
   - Voice/sound alerts:
     - “TRAFFIC, TRAFFIC”
     - “CLEAR OF CONFLICT”
     - maybe “TRAFFIC, TWO O’CLOCK, HIGH/LOW”
   - This is not real TCAS. It is ADS-B/TIS-B situational awareness only.

2. Airbus-style callout toy
   - Fun landing callouts:
     - “ONE HUNDRED”
     - “FIFTY”
     - “FORTY”
     - “THIRTY”
     - “TWENTY”
     - “RETARD, RETARD”
   - For a Piper Warrior, “FLARE” is more appropriate than “RETARD,” but “RETARD RETARD” is wanted as an Airbus joke/toy.
   - This should be entertainment/advisory only, not used for actual flare timing.
   - Real Airbus uses radar/radio altitude; this project will estimate height using baro + GPS + airport/runway elevation.

3. Approach quality / GPWS-style toy alerts
   - Possible sounds:
     - “SINK RATE”
     - “DON’T SINK”
     - “TOO LOW”
     - “TOO HIGH”
     - “TOO FAST”
     - “UNSTABLE”
     - “GO AROUND”
     - “MINIMUMS”
     - “CONTINUE”
   - Use barometric vertical speed, GPS groundspeed, runway proximity, and optional runway database.
   - Should have an arm/mute mechanism to avoid distraction.

4. Takeoff / phase-of-flight sounds
   - Possible callouts:
     - “AIRSPEED ALIVE” based on GPS groundspeed starting to increase.
     - “ROTATE” based on chosen groundspeed threshold, mostly as a toy.
     - “POSITIVE RATE” based on baro vertical speed.
     - “DON’T SINK” if losing altitude after takeoff.
   - Note: this is not real airspeed unless I add a pitot/airspeed system.

5. System status sounds
   - “SYSTEM TEST OK”
   - “GPS ACQUIRED”
   - “GPS LOST”
   - “ADS-B RECEIVER ONLINE”
   - “ADS-B LOST”
   - “TRAFFIC SYSTEM ONLINE”
   - “OVERHEAT” based on Pi CPU temp.
   - Need physical mute button, strongly recommended.

6. Button-triggered cockpit meme sounds
   - Physical buttons could trigger:
     - Airbus autopilot disconnect cavalry charge
     - Master caution chime
     - “PULL UP”
     - “TRAFFIC TRAFFIC”
     - “CLEAR OF CONFLICT”
     - “RETARD RETARD”
   - Buttons are easy and reduce dependency on sensor accuracy.

Data sources and integration:
1. Stratux ADS-B traffic
   - Best approach: do NOT decode SDR raw data directly.
   - Let Stratux decode traffic, then read Stratux outputs.
   - Possible data paths:
     - Stratux WebSocket `/traffic`, likely easiest for custom UI.
     - GDL90 UDP on port 4000, medium difficulty, same style used by EFB apps.
   - Example concept:
     `ADS-B antennas/SDRs -> Stratux decoder -> /traffic WebSocket -> Python TCAS UI -> HDMI display/audio`
   - Python could use `websockets` to connect to `ws://localhost/traffic` or `ws://192.168.10.1/traffic`.

2. GPS
   - USB GPS module can be used with Stratux.
   - Need to avoid two programs directly opening the raw GPS serial device.
   - Clean pattern:
     `USB GPS -> gpsd -> Stratux + my Python program`
   - `gpsd` allows multiple clients.
   - Read with `python3-gps` or gpsd JSON.
   - GPS gives:
     - latitude
     - longitude
     - GPS altitude, noisy
     - groundspeed
     - track over ground
   - Typical cheap USB GPS update rate is around 1 Hz; some u-blox modules can do 5–10 Hz.
   - GPS altitude is not precise enough for 20 ft landing callouts.

3. Barometric pressure sensor
   - Looking at SparkFun Qwiic BMP581 pressure sensor.
   - BMP581 is a good practical choice:
     - high-performance Bosch BMP5xx family
     - well-supported by SparkFun
     - Qwiic connector
     - I2C
     - Raspberry Pi compatible at 3.3 V
   - Use 3.3 V only, not 5 V.
   - Wiring to Raspberry Pi 4B:
     - BMP581 VCC/3V3 -> Pi pin 1, 3.3V
     - BMP581 GND -> Pi pin 6, GND
     - BMP581 SDA -> Pi pin 3, GPIO2/SDA
     - BMP581 SCL -> Pi pin 5, GPIO3/SCL
   - Enable I2C:
     `sudo raspi-config`
     `Interface Options -> I2C -> Enable`
   - Install tools:
     `sudo apt install i2c-tools`
   - Detect:
     `i2cdetect -y 1`
     likely address `0x46` or `0x47`.
   - SparkFun Python library:
     `pip3 install sparkfun-qwiic-bmp581`
   - Alternative library path:
     Adafruit CircuitPython BMP5xx supports BMP580/BMP581/BMP585 over I2C.
   - Bosch also has official BMP5 SensorAPI in C.
   - BMP581 vs BMP585:
     - BMP585 is rugged/sealed/protected for harsh environments, not an aerodynamic static-port solution.
     - “Sealed” does not prevent wind disturbance; enclosure/static-chamber design still matters.
   - BMP581 vs BMP3xx:
     - BMP5xx is newer and high-performance.
     - BMP390/BMP388 are older but easier/more common.
     - For this project, BMP581 is good; bigger errors will come from calibration, cabin/static pressure, heat, venting, and runway elevation reference.
   - Temperature/humidity sensor idea:
     - Adding a temperature/humidity sensor can make sense, but mainly as a refinement rather than the primary accuracy source.
     - Pressure-to-altitude conversion depends on the air column temperature profile and, to a smaller degree, humidity. A local temp/humidity reading can support a more realistic density/virtual-temperature correction than assuming standard atmosphere.
     - This is workable for improving trends and reducing some model error, especially for relative altitude/VSI and local field-elevation calibration.
     - It will not turn this into radar altitude or certified altitude. Larger errors will still come from static pressure sampling, sensor placement, cabin pressure effects, heat from the Pi/enclosure, calibration timing, QNH/METAR age, and runway/airport elevation reference.
     - If added, place the temp/humidity sensor near the baro static chamber but thermally isolated from the Pi, sun-heated enclosure walls, speaker, display/power-bank heat, and fan exhaust.
     - Practical sensors to consider later: Sensirion SHT31/SHT4x or Bosch BME280/BME688. Avoid relying on BME280 pressure as the primary pressure source if BMP581 is available; use it mostly for temperature/humidity.

4. Baro calibration and altitude logic
   - Baro sensor measures pressure, not true altitude.
   - Pressure changes can mean altitude change or weather pressure change.
   - Best architecture:
     - BMP581 pressure sensor = fast/smooth relative altitude and VSI.
     - GPS = rough absolute position/speed/track and slow drift sanity check.
     - airport/runway elevation database = reference for AGL estimate.
     - METAR altimeter setting = optional slow correction.
     - optional temperature/humidity sensor = small correction for air-density/virtual-temperature modeling, not a replacement for calibration.
     - physical CAL button = best practical calibration.
   - Recommended modes:
     1. Manual QNH mode: enter altimeter setting like 29.92/30.01.
     2. Field elevation mode: press CAL while parked; system sets current pressure to known airport elevation.
     3. METAR auto mode: parse nearest METAR altimeter setting when available from FIS-B/Stratux or internet.
   - For local pattern work, calibrating shortly before takeoff/landing should be decent.
   - Do not rely on baro/GPS callouts for real flare timing.

5. METAR / altimeter setting from Stratux
   - METAR altimeter setting appears as `A####`, e.g. `A2992` means 29.92 inHg.
   - This can be received via ADS-B weather/FIS-B on 978 MHz UAT.
   - Stratux may not expose METAR via a simple register.
   - It is more like a server/application:
     - possible local API endpoint if exposed
     - otherwise parse GDL90 UDP port 4000 / FIS-B weather products
     - or hack Stratux source to expose a local JSON endpoint
   - Useful idea:
     Add a custom Stratux endpoint like:
     `http://127.0.0.1/metar.json`
     returning:
     `{ "station": "KCHD", "raw": "... A2992", "altimeter_inhg": 29.92, "age_min": 12 }`
   - Need to inspect/hack active Stratux repo:
     `https://github.com/b3nn0/stratux`
   - Search source:
     `grep -R "METAR" -n .`
     `grep -R "FIS" -n .`
     `grep -R "weather" -n main godump978 dump978 web`
   - Do not build a full custom image first; better to modify/test live, then build custom image later.

6. AHRS / direction sensor
   - Stratux “direction”/attitude comes from AHRS/IMU board, especially magnetometer for heading.
   - AHRS includes gyro/accelerometer/magnetometer depending on board.
   - GPS track is direction of motion, not aircraft heading.
   - For toy TCAS version 1, AHRS is not required.
   - GPS ownship position + GPS track + ADS-B target positions are enough for:
     - north-up display
     - track-up display
     - distance/bearing
     - traffic alerts
   - AHRS helps later for:
     - heading-up display
     - artificial horizon
     - pitch/bank
     - better “traffic at 2 o’clock” while maneuvering/parked/taxiing
     - synthetic-vision look

Display/output:
- The portable charger/display has a built-in 1080p screen.
- Raspberry Pi 4B uses micro-HDMI; HDMI display output is easiest.
- A display is now connected to the Pi 4 micro-HDMI port farther from USB-C power, i.e. HDMI1.
- HDMI smoke test:
  - Script added at `/rwbase/playground/SpaceInvader/scripts/show_hdmi_test.sh` and local SSHFS path `~/stratux_pi/SpaceInvader/scripts/show_hdmi_test.sh`.
  - Initial `/dev/tty1` test did not show because the Pi had booted headless with no framebuffer: `display_power=0`, `get_lcd_info` returned `0 0 0 no display`, and `/dev/fb0` did not exist.
  - `/boot/firmware` is a real writable vfat boot partition (`/dev/mmcblk0p1`), not the temporary root overlay. The root filesystem itself is overlay-backed with tmpfs upperdir, while `/rwbase` is persistent ext4.
  - Added HDMI1 force block to `/boot/firmware/config.txt`:
    - `max_framebuffers=2`
    - `hdmi_force_hotplug:1=1`
    - `hdmi_group:1=2`
    - `hdmi_mode:1=82`
    - `hdmi_drive:1=2`
  - After reboot, HDMI came up: `display_power=1`, `get_lcd_info` returned `1920 1080 24`, and `/dev/fb0` existed as a 1920x1080 32-bit framebuffer with stride 7680.
  - Ran over SSH with `bash /rwbase/playground/SpaceInvader/scripts/show_hdmi_test.sh`.
  - The script switches to virtual console 1 where possible and writes a big `SPACEINVADER HDMI TEST` message to `/dev/tty1`.
  - Command reported: `Wrote HDMI test message to /dev/tty1.`
  - A temporary direct framebuffer color-bar test at `/rwbase/playground/SpaceInvader/scripts/fb0_color_test.py` succeeded with: `Drew color bars to /dev/fb0: 1920x1080, stride 7680.`
  - User initially saw nothing after the framebuffer write, then unplugged/replugged the HDMI cable/display and saw the color stripes. This confirms the physical HDMI1/display path works; the issue was likely hotplug/sync/cable/display-input state after boot/config changes.
  - On 2026-05-29, the user removed `fb0_color_test.py` because the HDMI/display path is now proven. Do not recreate it unless a new framebuffer smoke test is needed.
- No custom display driver should be needed for HDMI.
- A custom UI can be written in:
  - Python + pygame
  - Python + Qt
  - browser-based kiosk UI
- For simple color blocks/fullscreen UI, Linux framebuffer or pygame is enough.
- Stratux itself is headless and does not need a desktop environment, but an HDMI fullscreen app can be auto-launched.
- Important cockpit concerns:
  - sunlight readability
  - heat in Arizona cockpit
  - RF/GPS/SDR interference from power bank/display
  - Pi cooling/power stability

Audio:
- Raspberry Pi 4B can output audio over HDMI, USB audio, Bluetooth, or 3.5mm depending setup.
- HDMI audio is easy if display has speakers, but cockpit noise may make it hard to hear.
- Bluetooth speaker is possible, but may have latency, disconnects, auto-sleep, and annoying voice prompts.
- USB-only powered speaker is likely more reliable.
- Candidate discussed:
  - Logitech S150 USB speakers: USB audio + power, common/simple/loud enough for testing.
  - Tiny embedded USB speaker: better enclosure integration but may be too quiet.
- Need sounds to cut through headset/cockpit noise:
  - 1–3 kHz tones are better than bass.
  - Speech may be hard to hear unless speaker is near head.
- Best usability would be feeding audio to headset/intercom, but that is more complex and must not interfere with comms.
- Mandatory design idea: physical mute button.

Enclosure / CAD / 3D print design:
- I am designing a box to hold power bank + Raspberry Pi + possibly sensor/speaker.
- I have a 3D printer but am not a strong CAD user.
- Recommended lid/door:
  - slide-in lid is best beginner option.
  - screw-on lid also robust.
  - snap-fit and hinges are harder.
  - magnet retention is a good add-on.
- Slide-in lid considerations:
  - 0.3–0.5 mm clearance for average printer.
  - Avoid full-length tight contact; use small guide surfaces.
  - Add a stop feature/detent/magnet.
  - Chamfer rail entrance 0.5–1 mm.
  - Print box upright, lid flat if possible.
  - PETG is better than PLA for Arizona cockpit heat.
  - Chunky rails: 2.5–3 mm.
- Raspberry Pi fit:
  - use 0.5–1.0 mm clearance per side, or +1.0 to +2.0 mm total for easy fit.
  - better to mount with standoffs/posts instead of tight PCB friction fit.
  - real size includes USB/HDMI/GPIO/SD/heatsinks, not just PCB.
- Wall thickness:
  - main walls 2.5–3 mm
  - bottom 3 mm
  - lid 2–2.5 mm
  - rails 2.5–3 mm
  - with 0.4 mm nozzle, nice values include 2.4, 2.8, 3.2 mm.
- Baro sensor chamber:
  - Do not seal sensor airtight.
  - Do not use long twisted tunnel if responsiveness matters.
  - Use a small vented static chamber.
  - Multiple small side/bottom holes, 1–2 mm each, 2–6 holes.
  - Avoid front-facing scoop.
  - Keep sensor away from Pi CPU heat, fan exhaust, sun-heated wall, speaker vibration, USB dongle heat.
  - A tiny foam/breathable fabric filter is okay if not airtight.
  - The chamber should feel cabin static pressure with damped airflow, not direct blast.

Internet access for Stratux:
- Phone connected to Stratux Wi-Fi with cellular data ON does not automatically give Stratux internet.
- Better approaches:
  1. Phone hotspot; Stratux joins hotspot as Wi-Fi client and also creates AP: AP+Client mode.
  2. Add second USB Wi-Fi dongle: built-in Wi-Fi for Stratux AP, dongle for internet client.
  3. USB tether phone to Pi.
  4. Laptop has two networks: Wi-Fi to Stratux, Ethernet/phone tether for internet.
- For flying, keep Stratux simple/offline in AccessPoint mode.
- For development, AP+Client or external sync is okay.

Persistent Pi setup:
- Setup script was restarted from scratch on 2026-05-30 at user request.
- User must manually disable overlay protection and reboot before running setup:
  - `sudo overlayctl disable`
  - `sudo reboot`
- Current setup script:
  - path: `scripts/setup_pi_overlay.sh`
  - must be run as root with overlay disabled
  - refuses to run if `/` is still mounted as filesystem type `overlay`
  - step 1: checks/corrects the Pi system clock using the HTTP `Date` header from `http://deb.debian.org/debian/`, because apt may fail with `Release file ... is not valid yet` if the Pi clock is behind
  - step 2: runs `apt-get update`, `apt-get upgrade -y`, `apt-get autoremove -y`, and `apt-get clean`
  - step 3: skips Argon ONE driver install for now; `install_argon_one_driver` remains in the script, but the call is commented out
  - step 4: installs `python3-full` and `python3-pygame` with apt
  - step 5: creates/updates project virtual environment at `.venv` with `--system-site-packages`
- All project Python should run inside `.venv`, not directly against system Python:
  - activate with `source /rwbase/playground/SpaceAvoider/.venv/bin/activate`
  - then use `python ...` or `python -m pip ...`
- Display dependency note:
  - pip `pygame-ce` 2.5.7 on the Stratux Pi only exposed SDL `offscreen` and `dummy` drivers during testing, so it could not draw to HDMI.
  - apt `python3-pygame` through the venv uses the system SDL stack, but this Stratux image still reported `kmsdrm not available` and no visible `linuxfb` driver.
  - `display_helper.py` now keeps pygame as the drawing library while falling back to direct `/dev/fb0` writes when SDL cannot open HDMI.
- Audio dependency note:
  - `audio_helper.py` uses `pygame.mixer`, so no setup-script dependency change was needed after `python3-pygame` was installed.
  - `aplay -l` showed HDMI as card 0 and the 3.5 mm jack as card 1 `Headphones`.
  - SDL/pygame names the headphone output `bcm2835 Headphones, bcm2835 Headphones`.
  - `audio_helper.py` defaults to that headphone-jack device; use `--system-default` only when intentionally testing the Pi default output.
  - Verified on the Pi with `python -m code.helper.audio_helper --volume 0.8`; it started playback successfully through the headphone device.
- After setup, user manually re-enables overlay protection and reboots:
  - `sudo overlayctl enable`
  - `sudo reboot`
- Historical note from earlier setup script work:
  - The Pi clock can be behind after boot, causing apt errors like `Release file ... is not valid yet`.
  - `python3-full` was too large for the small live overlay when overlay was enabled because it pulls docs/examples/IDLE/Tk. New workflow avoids that by requiring overlay disabled before running.
  - Prefer a project `.venv` for Python modules and avoid system `pip install` on externally managed Python.

Important safety/human factors:
- This project must not distract during actual flight training.
- It is a toy/advisory display only.
- Do not call it real TCAS in any safety/legal/operational sense.
- ADS-B traffic has limitations:
  - coverage gaps
  - aircraft without ADS-B Out
  - TIS-B dependency
  - latency
  - receiver/software/display failures
- Baro/GPS callouts are not radio altitude and not certified.
- Use physical mute/off switch.
- In training flights, do not let joke sounds trigger unexpectedly.
- The certified aircraft instruments, CFI, see-and-avoid, and normal procedures remain primary.

Near-term implementation plan:
1. Get source-code workflow working:
   - Prefer local VS Code/Codex with SSHFS-Win or SFTP sync.
   - Avoid installing big VS Code Server on Stratux until overlay/storage issue is solved.
2. Create basic Python app on Pi:
   - Connect to Stratux `/traffic` WebSocket or parse GDL90 later.
   - Print nearby traffic list first.
3. Add simple pygame display:
   - black background
   - ownship center
   - range rings
   - traffic symbols
   - relative altitude labels
   - threat color/size
   - First pygame smoke test can run with:
     `python -m code.helper.display_helper --seconds 30`
   - `display_helper.py` defaults to fullscreen and uses SDL `kmsdrm` when no desktop `DISPLAY`/`WAYLAND_DISPLAY` exists; if SDL cannot open a visible console display, it falls back to pygame Surface rendering plus direct `/dev/fb0` output. Force that path with `--backend fb0`.
4. Add audio:
   - local `.wav` files
   - play with pygame mixer
   - add rate limiting and mute button
5. Add GPS:
   - read via gpsd, not raw serial if Stratux uses it.
6. Add BMP581:
   - I2C wiring, SparkFun Python library, pressure readings.
   - compute relative altitude and VSI.
7. Add calibration:
   - CAL button sets current pressure to field elevation.
   - optional METAR parser later.
8. Add callouts:
   - only armed near runway or by manual button.
   - “100/50/40/30/20/RETARD” toy mode.
9. Later:
   - inspect/hack Stratux source to expose METAR/FIS-B via local endpoint.
   - possibly build custom Stratux image once modifications are proven.
