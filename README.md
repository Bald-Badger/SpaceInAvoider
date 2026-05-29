# SpaceInvader
this is my personal repo to build a toy TCAS system around my raspberry pi based on stratux ADS-B system

## Pi setup

Run persistent Stratux/Raspberry Pi setup from the Pi:

```bash
sudo bash /rwbase/playground/SpaceInvader/scripts/setup_pi_overlay.sh
```

The setup script is designed for the Stratux overlay filesystem. It applies
changes to the live root for the current boot and to `/overlay/robase` so they
survive reboot.

When a project Python module is missing, add it to `PYTHON_PIP_PACKAGES` in the
setup script. If that module needs system libraries, add the matching apt
packages to `SYSTEM_APT_PACKAGES`.

The first project renderer dependency is `pygame-ce`, installed into
`.venv`. Import it from Python as `pygame`.

Use the project virtual environment instead of system Python:

```bash
source /rwbase/playground/SpaceInvader/.venv/bin/activate
python -c "import pygame; print(pygame.version.ver)"
```

Or run through the wrappers:

```bash
/rwbase/playground/SpaceInvader/scripts/project_python.sh -c "import pygame; print(pygame.version.ver)"
/rwbase/playground/SpaceInvader/scripts/project_pip.sh list
```
