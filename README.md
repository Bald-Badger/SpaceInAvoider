# SpaceAvoider

Personal Raspberry Pi / Stratux toy traffic-awareness and avionics-display project.

## Persistent Pi Setup

Persistent Stratux/Raspberry Pi setup starts by manually disabling overlay
protection and rebooting.

Disable overlay protection, then reboot:

```bash
sudo overlayctl disable
sudo reboot
```

Run the setup script:

```bash
cd /rwbase/playground/SpaceAvoider
sudo bash scripts/setup_pi_overlay.sh
```

The setup script currently:

1. Checks/corrects the Pi system clock using the HTTP `Date` header from `http://deb.debian.org/debian/`.
2. Runs `apt-get update`, `apt-get upgrade -y`, `apt-get autoremove -y`, and `apt-get clean`.
3. Skips the Argon ONE driver install for now; the installer call is left commented in the setup script.
4. Installs `python3-full` and Raspberry Pi/Debian `python3-pygame`.
5. Creates/updates the project Python virtual environment at `.venv` with system site packages enabled.

All project Python should run from `.venv`, not directly from system Python:

```bash
source /rwbase/playground/SpaceAvoider/.venv/bin/activate
python -c "import sys, pygame; print(sys.executable); print(pygame.version.ver)"
```

The display helper uses `pygame` from the system package through the venv.
On this Stratux Pi, SDL may not expose a visible console video driver, so the
helper can also render with pygame into an in-memory surface and write the
result directly to `/dev/fb0`.

Run the first pygame display helper:

```bash
cd /rwbase/playground/SpaceAvoider
source .venv/bin/activate
python -m code.helper.display_helper --seconds 30
```

Force the direct framebuffer path if SDL display setup fails:

```bash
python -m code.helper.display_helper --backend fb0 --seconds 30
```

Play the first audio callout helper:

```bash
python -m code.helper.audio_helper --volume 0.8
```

The audio helper defaults to the Raspberry Pi headphone jack:
`bcm2835 Headphones, bcm2835 Headphones`.

Re-enable overlay protection, then reboot:

```bash
sudo overlayctl enable
sudo reboot
```

Check protected overlay behavior:

```bash
df -h /overlay/rwdata
```
