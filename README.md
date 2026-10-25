# Ender-3 V3 KE — Three-camera MJPEG setup with auto-recovery

**Real-world configuration for Logitech C270, Creative USB webcam and Creality Nebula, using Creality Helper Script, Entware, Mainsail and `mjpg_streamer`.**

> **Status:** Working on one Ender-3 V3 KE as of October 2026. This is an example of a working setup, **not** a universal plug-and-play installer. Read the entire guide, back up your files and adjust device paths, resolutions, ports and binary locations for your own printer before starting services. Root/SSH access is required. Do not run commands blindly on a different model or firmware.

## Why I am sharing this

This setup was developed through many hours of troubleshooting, trial and error, and testing on my own printer, working together with **ChatGPT as a technical assistant**. We encountered cameras disappearing after USB re-enumeration, streams that failed while a process still existed, and configuration issues with multiple camera instances. Eventually we got all three cameras running together and added a recovery watchdog.

I hope the detailed configuration below saves somebody else time. I am a hobbyist, not a professional developer; please treat the scripts as a documented working example, not a guaranteed fix for every installation.

## Environment used for testing

- Printer: **Creality Ender-3 V3 KE** (F005 board), rooted; stock Creality screen retained
- Firmware reported on this printer: **1.1.0.17**
- Creality Helper Script, **USB Camera Support**, Entware, Moonraker and Mainsail installed
- Mainsail web interface: port **4409**
- Printer's underlying OS: Buildroot / BusyBox
- A locally working `mjpg_streamer` executable and the plugins `input_uvc.so` and `output_http.so` are in **`/usr/data/camera-logitech/`**
- This build is launched with **`/opt/lib/ld.so.1 --library-path /opt/lib:/usr/lib`**
- Custom service scripts in **`/opt/etc/init.d/`**, started through the printer's existing Entware init integration
- Watchdog executed by cron using **`/usr/data/camera-watchdog/crontabs/`**

**Important prerequisite:** The working `mjpg_streamer` executable and plugins are **not included** here. Their binary compatibility, location and method of installation vary. These scripts will not work if you merely copy the shell files without a working streamer and its dependencies. Start with the Helper Script's documented USB Camera Support installation, then confirm the actual binary/plugin paths. Some users have reported missing Entware `mjpg-streamer` packages, so do not assume those packages are available in every environment.

Useful references:

- [Creality Helper Script — USB Camera Support](https://guilouz.github.io/Creality-Helper-Script-Wiki/helper-script/usb-camera-support/)
- [Creality Helper Script — camera configuration](https://guilouz.github.io/Creality-Helper-Script-Wiki/configurations/configure-camera/)
- [Community discussion: second camera not displaying on 8081](https://github.com/Guilouz/Creality-Helper-Script-Wiki/discussions/809)
- [Community discussion: missing mjpg-streamer packages](https://github.com/Guilouz/Creality-Helper-Script-Wiki/discussions/894)

## Camera-to-port mapping (my specific hardware)

| Camera | USB by-path suffix | HTTP port | Resolution and FPS *requested* in service |
|---|---|---:|---|
| Logitech C270 | `0:1.1.3:1.0-video-index0` | `8080` | `1280x720`, 15 FPS |
| Creative Live! Cam Sync 1080p V | `0:1.1.2:1.0-video-index0` | `8081` | `640x480`, 15 FPS |
| Creality Nebula | `0:1.1.4:1.0-video-index0` | `8082` | `1280x720`, 15 FPS |

**Requested FPS is not necessarily actual FPS.** The Creative webcam in particular can deliver fewer frames depending on mode, USB conditions and client. All devices were running simultaneously, but no formal long-term performance or throughput benchmark has been made.

## 1. Diagnose your devices **before changing anything**

SSH into the printer as root and run:

```sh
ls -l /dev/v4l/by-path/
ls -l /dev/video*
ps | grep '[m]jpg_streamer'
```

Use `readlink -f` to find where each symlink currently points:

```sh
readlink -f /dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.2:1.0-video-index0
readlink -f /dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.3:1.0-video-index0
readlink -f /dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.4:1.0-video-index0
```

These paths are **examples from my exact USB topology**. They will be different on another hub/USB port/printer. Also note that some webcams expose multiple `/dev/videoX` entries, but only one may provide the usable video stream; verify the actual camera device before using it.

Why use `/dev/v4l/by-path/`? The kernel can rename a webcam from `/dev/video5` to `/dev/video7` on reconnection; a path symlink tied to the same physical connection can remain more predictable. However, the **by-path** name can itself change if you move the camera to another USB port or change the hub topology.

Verify that the streamer and plugin files exist at the paths in the scripts:

```sh
ls -l /usr/data/camera-logitech/mjpg_streamer
ls -l /usr/data/camera-logitech/input_uvc.so
ls -l /usr/data/camera-logitech/output_http.so
ls -l /opt/lib/ld.so.1
```

If these are missing, **stop here** and locate/install a compatible build first; do not copy binaries intended for an unrelated architecture.

Before starting new camera services, check for an existing Helper Script camera service or another `mjpg_streamer` already listening on a chosen port. Two processes cannot bind the same HTTP port. Decide which instance should own each port and back up existing service files before modifying them.

## 2. Back up existing configuration

```sh
mkdir -p /usr/data/multicam-backup
for f in /opt/etc/init.d/S99camera_logitech \
         /opt/etc/init.d/S98camera_creative \
         /opt/etc/init.d/S99camera_nebula \
         /usr/data/camera-watchdog/watchdog.sh; do
    if [ -f "$f" ]; then
        cp -p "$f" /usr/data/multicam-backup/
    fi
done
```

If an older script has the same name, inspect and save it first. Back up other camera services and Mainsail/Moonraker settings separately if you intend to alter them. No printer firmware changes are part of this guide.

## 3. Adapt and install the three camera service scripts

The working shell files are included in the **`scripts/`** directory of the downloadable project and reproduced in full in the **Script appendix** at the bottom of this standalone README:

| File in this repository | Destination on printer |
|---|---|
| `scripts/S99camera_logitech` | `/opt/etc/init.d/S99camera_logitech` |
| `scripts/S98camera_creative` | `/opt/etc/init.d/S98camera_creative` |
| `scripts/S99camera_nebula` | `/opt/etc/init.d/S99camera_nebula` |

**Edit the files first**, especially the camera symlinks (`-d ...` and `*_LINK=`), stream resolution/FPS, port, `mjpg_streamer` path and `/opt/lib/ld.so.1` loader path.

You can create these files on the printer by copying the appendix scripts into their exact respective locations using your preferred SSH file editor, or download the project bundle on a Linux PC, `cd` into the directory containing the files, and use **SCP from that PC** (not from the printer):

```sh
scp scripts/S99camera_logitech scripts/S98camera_creative scripts/S99camera_nebula \
    root@PRINTER_IP:/opt/etc/init.d/
```

Replace `PRINTER_IP` with the printer's actual LAN address. Alternatively use SFTP or your preferred SSH file transfer tool. On the printer:

```sh
chmod 755 /opt/etc/init.d/S99camera_logitech
chmod 755 /opt/etc/init.d/S98camera_creative
chmod 755 /opt/etc/init.d/S99camera_nebula
```

### What each service does

- **Logitech (`8080`):** Launches `mjpg_streamer` with a persistent by-path input and uses a PID file to avoid starting another instance when that PID is alive.
- **Creative (`8081`):** Resolves its by-path symlink to the actual character device and looks through `/proc/*/cmdline` for an existing streamer instance on its port.
- **Nebula (`8082`):** Uses the same approach as Creative but with its own camera link and port.

The `check` subcommands in these examples are **process checks**, not video-health checks; the watchdog below tests actual HTTP snapshots.

### Start and verify one camera at a time

On the printer, and **only after resolving any existing port conflicts**:

```sh
sh /opt/etc/init.d/S99camera_logitech start
sh /opt/etc/init.d/S98camera_creative start
sh /opt/etc/init.d/S99camera_nebula start
```

Test snapshots locally on the printer (these commands work with the BusyBox `wget` used on my device):

```sh
for port in 8080 8081 8082; do
    if wget -q -T 5 -O /dev/null "http://127.0.0.1:$port/?action=snapshot"; then
        echo "Camera $port: OK"
    else
        echo "Camera $port: FAILED"
    fi
done
```

If a camera fails, troubleshoot that camera's symlink, available resolution/format, binary dependencies, existing streamer processes and port collisions **before** proceeding. A successful snapshot confirms the local HTTP endpoint responds, not that all clients or remote proxies can reach it.

### Start automatically after reboot

My printer already had working **Entware startup integration** (including its `S50unslung` boot integration), so its `/opt/etc/init.d/` services are started via the configured init flow. **Merely copying scripts into this folder does not guarantee automatic startup on every firmware.** Verify your own Entware/Buildroot boot mechanism and check all three streams after a full printer reboot. Avoid installing a second camera startup mechanism on a printer that already starts the same processes.

## 4. Configure Mainsail webcams

In **Mainsail → Settings → Webcams**, add one entry per camera. The tested direct local network endpoints are:

| Camera | Stream URL | Snapshot URL |
|---|---|---|
| Logitech | `http://PRINTER_IP:8080/?action=stream` | `http://PRINTER_IP:8080/?action=snapshot` |
| Creative | `http://PRINTER_IP:8081/?action=stream` | `http://PRINTER_IP:8081/?action=snapshot` |
| Nebula | `http://PRINTER_IP:8082/?action=stream` | `http://PRINTER_IP:8082/?action=snapshot` |

Replace `PRINTER_IP` with the real LAN address. Depending on your Mainsail, proxy, HTTPS, mobile or remote access configuration, a **relative/proxied camera URL** may be more appropriate than a private LAN IP. The Helper Script documents `/webcam/` and `/webcam2/` proxies; do not assume a third proxy exists without checking your web server configuration.

### OrcaSlicer-on-Linux issue we encountered

On Pop!_OS, **OrcaSlicer Flatpak 2.5.0-alpha** (and also 2.4.2 stable during testing) did not render the cameras with Mainsail's standard **`MJPEG-Streamer`** service selected. Mainsail in a regular browser and mobile viewing worked.

Changing the Mainsail camera **Service** to `Adaptive MJPEG-Streamer (experimental)` made video appear inside OrcaSlicer, but remote/mobile FPS became very low (approximately 1–3 FPS in our tests).

**The tested workaround for this setup was selecting `UV4L-MJPEG` for the camera Service in Mainsail, while keeping the same Stream and Snapshot URLs.** All three cameras then appeared in OrcaSlicer, the browser and the mobile viewer with good performance. This is a **client display/service selection**, not a replacement for the `mjpg_streamer` backend running on the printer.

This workaround may be unrelated to some 8081 problems: first ensure that the camera stream itself responds to `?action=snapshot` on the printer.

## 5. Optional watchdog with recovery

We also experienced cameras disappearing while a print continued, even when streamer processes appeared to be alive. Our watchdog queries each **local snapshot endpoint**, rather than trusting the PID alone.

Working file: **`scripts/watchdog.sh`** (also reproduced in the appendix).

| Watchdog behavior | Actual setting |
|---|---|
| Check frequency | Once per minute through cron |
| When a camera responds | Reset that camera's failure count |
| When a camera fails | Increment separate failure count |
| Restart threshold | Three successive failed checks |
| Recovery opt-in | `/usr/data/camera-watchdog/enable-recovery` must exist |
| Cooldown | Five minutes between restart attempts per camera |
| USB device absent | Report `USB device missing`; do not attempt restart |
| After invoking restart | Failure count resets; verify the service really recovered in subsequent checks |

Install the script, adapting its **USB path map**, ports and service paths to your own setup:

From your Linux PC:

```sh
ssh root@PRINTER_IP 'mkdir -p /usr/data/camera-watchdog/crontabs'
scp scripts/watchdog.sh root@PRINTER_IP:/usr/data/camera-watchdog/watchdog.sh
```

On the printer:

```sh
chmod 755 /usr/data/camera-watchdog/watchdog.sh
/bin/sh /usr/data/camera-watchdog/watchdog.sh
```

Initially leave recovery **disabled** (no `enable-recovery` file) and make sure it prints `logitech: OK`, `creative: OK`, `nebula: OK` consistently.

After verifying that all three separate service `restart` commands work, you may opt into automatic recovery:

```sh
touch /usr/data/camera-watchdog/enable-recovery
```

To disable automatic restarts without disabling monitoring:

```sh
rm -f /usr/data/camera-watchdog/enable-recovery
```

### Cron

The tested cron entry (also in `scripts/cron-entry.txt` in the downloadable project) is:

```cron
* * * * * /bin/sh /usr/data/camera-watchdog/watchdog.sh >> /usr/data/camera-watchdog/watchdog.log 2>&1
```

**Add** this line to the correct cron file for your configuration (our printer used `/usr/data/camera-watchdog/crontabs/root`); **do not overwrite** existing jobs. Our printer additionally scheduled `/usr/data/camera-watchdog/rotate-log.sh` hourly, but its contents have **not** been reviewed or included in this repository, so that optional log-rotation job is not part of these installation instructions.

Check whether cron is already running before starting another instance:

```sh
ps | grep '[c]rond'
```

In our environment, cron was run with:

```sh
/usr/sbin/crond -b -c /usr/data/camera-watchdog/crontabs
```

Running that command again while cron is already active may start an unwanted duplicate. **Cron's automatic startup after reboot must also be configured and tested separately**; creating its crontab alone is not enough.

Review log output:

```sh
tail -n 30 /usr/data/camera-watchdog/watchdog.log
```

If the recovery flag is absent, the watchdog only **monitors**. If present, it can issue a restart after the three-failure threshold; this behavior is best tested while the printer is idle and not during an important print.

## 6. Troubleshooting checklist

**The second camera does not show on `8081`:**

1. Does `readlink -f` resolve the chosen camera symlink to a real `/dev/videoX` character device?
2. Does `wget -q -T 5 -O /dev/null 'http://127.0.0.1:8081/?action=snapshot'` succeed on the printer?
3. Is there already a different `mjpg_streamer` process using port `8081`?
4. Is the camera actually supported at the chosen resolution and frame rate?
5. Did you update the **Creative camera path** and port in **both** its init script and the watchdog?
6. If the local snapshot works but a Mainsail/Orca/mobile client does not, check the client URL, relative proxying, HTTP/HTTPS origin, and the selected Mainsail Service.

**The camera disappears after a USB reconnection:**

- Check `ls -l /dev/v4l/by-path/`; if you changed the hub port, update the script paths.
- Do not rely on fixed `/dev/video5`, `/dev/video6` or `/dev/video7` numbering.
- A running PID does not mean the stream is responsive; use the snapshot health check.

**The watchdog never restarts a camera:**

- Does `/usr/data/camera-watchdog/enable-recovery` exist?
- Have at least three checks failed in succession?
- Is the five-minute cooldown active?
- Does the device path exist? The watchdog intentionally refuses restarts if the character device is missing.
- Is cron actually running and executing the correct crontab?

**The service works manually but not after power cycling:**

- Verify Entware/init integration, executable permissions, and actual service startup.
- Verify cron startup separately.
- Do not assume your printer uses the same init layout as mine.

## Security and compatibility notes

- Direct HTTP ports `8080`–`8082` shown here were used on a trusted local network. **Do not expose unauthenticated camera HTTP endpoints directly to the public internet.** Use an appropriately secured reverse proxy or remote access solution.
- No credentials, private addresses, tokens or personal IDs are required by this guide.
- Device paths and ELF loader paths are **printer/USB/firmware-specific**. The copied files intentionally retain my working values as examples; adjust them **before** running.
- All example scripts were transcribed from files running on my printer; they have **not** been retested as a clean-install package on someone else's device.
- The watchdog performs practical recovery, not sophisticated health management. It cannot fix power failures, corrupted drivers, physically disconnected cameras or all USB issues.
- Keep backups. Inspect scripts before executing them as root.

## Acknowledgements

Thanks to the maintainers of the [Creality Helper Script](https://github.com/Guilouz/Creality-Helper-Script), Mainsail, Moonraker, `mjpg_streamer`, and the broader open-source community. This configuration was developed and tested through an extended **human + ChatGPT troubleshooting collaboration**. The hardware testing, observations and final confirmation were done on my own printer.

If this helps you, feel free to share your hardware details and any improvements in the relevant community discussion.


---

## Appendix — Complete scripts from the tested printer

These are the **exact service/watchdog script contents** that were inspected on the working printer. They still contain the device paths and runtime assumptions specific to that printer. Do not run them unchanged on different hardware.

### `S99camera_logitech`

```sh
#!/bin/sh

camera_logitech_service() {
    CAMDIR=/usr/data/camera-logitech
    PIDFILE=/usr/data/camera-logitech/mjpg_streamer.pid

    case "$1" in
        start)
            if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                echo "Logitech camera is already running."
                return 0
            fi

            echo "Starting Logitech C270 on port 8080..."
            /opt/lib/ld.so.1 --library-path /opt/lib:/usr/lib \
                "$CAMDIR/mjpg_streamer" \
                -i "$CAMDIR/input_uvc.so -d /dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.3:1.0-video-index0 -r 1280x720 -f 15" \
                -o "$CAMDIR/output_http.so -p 8080" &

            echo $! > "$PIDFILE"
            ;;
        stop|kill)
            if [ -f "$PIDFILE" ]; then
                PID=$(cat "$PIDFILE")
                if kill -0 "$PID" 2>/dev/null; then
                    kill "$PID"
                fi
                rm -f "$PIDFILE"
                echo "Logitech camera stopped."
            fi
            ;;
        check)
            [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
            return $?
            ;;
        restart)
            camera_logitech_service stop
            camera_logitech_service start
            return $?
            ;;
        reconfigure)
            return 0
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|check|reconfigure|kill}" >&2
            return 1
            ;;
    esac

    return 0
}

camera_logitech_service "$1"
```

### `S98camera_creative`

```sh
#!/bin/sh

creative_camera_service() {
    CREATIVE_CAMDIR=/usr/data/camera-logitech
    CREATIVE_PIDFILE=/usr/data/camera-logitech/mjpg_streamer_creative.pid
    CREATIVE_LINK=/dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.2:1.0-video-index0

    find_creative_camera() {
        for CREATIVE_FILE in /proc/[0-9]*/cmdline; do
            [ -r "$CREATIVE_FILE" ] || continue
            CREATIVE_CMD=$(tr '\000' ' ' < "$CREATIVE_FILE" 2>/dev/null)
            case "$CREATIVE_CMD" in
                *mjpg_streamer*"-p 8081"*)
                    CREATIVE_FOUND=${CREATIVE_FILE#/proc/}
                    CREATIVE_FOUND=${CREATIVE_FOUND%/cmdline}
                    echo "$CREATIVE_FOUND"
                    return 0
                    ;;
            esac
        done
        return 1
    }

    case "$1" in
        start)
            CREATIVE_PID=$(find_creative_camera)
            if [ -n "$CREATIVE_PID" ]; then
                echo "$CREATIVE_PID" > "$CREATIVE_PIDFILE"
                echo "Creative camera is already running (PID $CREATIVE_PID)."
                return 0
            fi

            CREATIVE_DEVICE=$(/usr/bin/readlink -f "$CREATIVE_LINK")
            if [ ! -c "$CREATIVE_DEVICE" ]; then
                echo "Creative camera device not found: $CREATIVE_LINK" >&2
                return 1
            fi

            echo "Starting Creative camera on $CREATIVE_DEVICE, port 8081..."
            /opt/lib/ld.so.1 --library-path /opt/lib:/usr/lib \
                "$CREATIVE_CAMDIR/mjpg_streamer" \
                -i "$CREATIVE_CAMDIR/input_uvc.so -d $CREATIVE_DEVICE -r 640x480 -f 15" \
                -o "$CREATIVE_CAMDIR/output_http.so -p 8081" &

            echo $! > "$CREATIVE_PIDFILE"
            ;;
        stop|kill)
            CREATIVE_PID=$(find_creative_camera)
            if [ -n "$CREATIVE_PID" ]; then
                kill "$CREATIVE_PID"
                echo "Creative camera stopped."
            fi
            rm -f "$CREATIVE_PIDFILE"
            ;;
        check)
            find_creative_camera >/dev/null
            return $?
            ;;
        restart)
            creative_camera_service stop
            creative_camera_service start
            return $?
            ;;
        reconfigure)
            return 0
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|check|reconfigure|kill}" >&2
            return 1
            ;;
    esac
    return 0
}

creative_camera_service "$1"
```

### `S99camera_nebula`

```sh
#!/bin/sh

nebula_camera_service() {
    NEBULA_CAMDIR=/usr/data/camera-logitech
    NEBULA_PIDFILE=/usr/data/camera-logitech/mjpg_streamer_nebula.pid
    NEBULA_LINK=/dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.1.4:1.0-video-index0

    find_nebula_camera() {
        for NEBULA_FILE in /proc/[0-9]*/cmdline; do
            [ -r "$NEBULA_FILE" ] || continue
            NEBULA_CMD=$(tr '\000' ' ' < "$NEBULA_FILE" 2>/dev/null)
            case "$NEBULA_CMD" in
                *mjpg_streamer*"-p 8082"*)
                    NEBULA_FOUND=${NEBULA_FILE#/proc/}
                    NEBULA_FOUND=${NEBULA_FOUND%/cmdline}
                    echo "$NEBULA_FOUND"
                    return 0
                    ;;
            esac
        done
        return 1
    }

    case "$1" in
        start)
            NEBULA_PID=$(find_nebula_camera)
            if [ -n "$NEBULA_PID" ]; then
                echo "$NEBULA_PID" > "$NEBULA_PIDFILE"
                echo "Nebula camera is already running (PID $NEBULA_PID)."
                return 0
            fi

            NEBULA_DEVICE=$(/usr/bin/readlink -f "$NEBULA_LINK")
            if [ ! -c "$NEBULA_DEVICE" ]; then
                echo "Nebula camera device not found: $NEBULA_LINK" >&2
                return 1
            fi

            echo "Starting Nebula camera on $NEBULA_DEVICE, port 8082..."
            /opt/lib/ld.so.1 --library-path /opt/lib:/usr/lib \
                "$NEBULA_CAMDIR/mjpg_streamer" \
                -i "$NEBULA_CAMDIR/input_uvc.so -d $NEBULA_DEVICE -r 1280x720 -f 15" \
                -o "$NEBULA_CAMDIR/output_http.so -p 8082" &

            echo $! > "$NEBULA_PIDFILE"
            ;;
        stop|kill)
            NEBULA_PID=$(find_nebula_camera)
            if [ -n "$NEBULA_PID" ]; then
                kill "$NEBULA_PID"
                echo "Nebula camera stopped."
            fi
            rm -f "$NEBULA_PIDFILE"
            ;;
        check)
            find_nebula_camera >/dev/null
            return $?
            ;;
        restart)
            nebula_camera_service stop
            nebula_camera_service start
            return $?
            ;;
        reconfigure)
            return 0
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|check|reconfigure|kill}" >&2
            return 1
            ;;
    esac
    return 0
}

nebula_camera_service "$1"
```

### `watchdog.sh`

```sh
#!/bin/sh

BASE=/usr/data/camera-watchdog

for CAM in logitech creative nebula; do
    case "$CAM" in
        logitech)
            PORT=8080
            USB=1.1.3
            SERVICE=/opt/etc/init.d/S99camera_logitech
            ;;
        creative)
            PORT=8081
            USB=1.1.2
            SERVICE=/opt/etc/init.d/S98camera_creative
            ;;
        nebula)
            PORT=8082
            USB=1.1.4
            SERVICE=/opt/etc/init.d/S99camera_nebula
            ;;
    esac

    LINK="/dev/v4l/by-path/platform-13500000.otg_new-usb-0:$USB:1.0-video-index0"
    FAILFILE="$BASE/$CAM.fail"
    LASTFILE="$BASE/$CAM.lastrestart"

    if wget -q -T 3 -O /dev/null \
        "http://127.0.0.1:$PORT/?action=snapshot"; then
        echo 0 > "$FAILFILE"
        echo "$CAM: OK"
        continue
    fi

    FAILS=$(cat "$FAILFILE" 2>/dev/null)
    case "$FAILS" in
        ''|*[!0-9]*) FAILS=0 ;;
    esac

    FAILS=$((FAILS + 1))
    echo "$FAILS" > "$FAILFILE"
    echo "$CAM: FAILED ($FAILS)"

    [ "$FAILS" -lt 3 ] && continue
    [ ! -f "$BASE/enable-recovery" ] && continue

    DEVICE=$(readlink -f "$LINK")
    if [ ! -c "$DEVICE" ]; then
        echo "$CAM: USB device missing"
        continue
    fi

    NOW=$(date +%s)
    LAST=$(cat "$LASTFILE" 2>/dev/null)

    case "$LAST" in
        ''|*[!0-9]*) LAST=0 ;;
    esac

    if [ $((NOW - LAST)) -lt 300 ]; then
        echo "$CAM: cooldown active"
        continue
    fi

    echo "$NOW" > "$LASTFILE"
    echo "$CAM: restarting service"
    sh "$SERVICE" restart
    echo 0 > "$FAILFILE"
done
```
