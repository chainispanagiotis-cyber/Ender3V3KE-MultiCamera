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
