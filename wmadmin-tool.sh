#!/bin/bash
#
# ============================================================
# Program name : wmadmin-tool.sh
# Version      : 1.1.4
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# Last modified: 2026-01-06
#
# Copyleft (ↄ) 2026 Arson Marianus
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License v3 or later.
# ============================================================

set -e

VERSION="1.1.4"

usage() {
    echo "Usage:"
    echo "  $0 install   --dir <webmethods_root>"
    echo "  $0 uninstall --dir <webmethods_root>"
    echo "  $0 version"
    exit 1
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

need_root() {
    [[ $EUID -eq 0 ]] || error "This step requires root. Please re-run with sudo."
}

case "$1" in
    install|uninstall) MODE="$1"; shift ;;
    version) echo "$VERSION"; exit 0 ;;
    *) usage ;;
esac

[[ "$1" == "--dir" ]] || usage
shift

TARGET_DIR="$1"
[[ -n "$TARGET_DIR" ]] || usage
TARGET_DIR="$(readlink -f "$TARGET_DIR")"

ADDONS_DIR="$TARGET_DIR/addons"
BIN_DIR="/usr/local/bin"

[[ -d "$TARGET_DIR" ]] || error "Directory '$TARGET_DIR' does not exist."

INSTALLER_KEY="$TARGET_DIR/IntegrationServer/bin/installerKey.sh"
[[ -f "$INSTALLER_KEY" ]] || error "Invalid Integration Server installation."


if [[ "$MODE" == "uninstall" ]]; then
    need_root
    echo "[INFO] Uninstalling wm admin tools"

    rm -rf "$ADDONS_DIR"

    for f in wmcreate wmdelete wmlist wmstart wmstop wmservice; do
        rm -f "$BIN_DIR/$f"
    done

    echo "[SUCCESS] wm admin tools uninstalled"
    exit 0
fi

echo "[INFO] Installing wm admin tools into $ADDONS_DIR"

rm -rf "$ADDONS_DIR"
mkdir -p "$ADDONS_DIR"
cd "$ADDONS_DIR"


cat > wm.cnf <<EOF
# ============================================================
# Program name : wm.cnf
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

export INST_DIR="$TARGET_DIR/IntegrationServer/instances"
EOF

cat > wmcreate <<'EOF'
#!/bin/bash
#
# ============================================================
# Program name : wmcreate
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

BASE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$BASE_DIR/wm.cnf"

IS_NAME="$1"

if [[ -z "${IS_NAME// }" ]]
then
    echo "Integration server cannot be empty."
    echo "Syntax:"
    echo "    wmcreate <integrationServerName>"
    echo
    echo "Correct and reissue the command."
    exit 1
fi

J_PORT="8075"
P_PORT="5555"
D_PORT="9555"

SS_LIST="$(ss -tulpn | grep LISTEN | awk '{print $5}' | grep -oE ':5[0-9]{3}|:8[0-9]{3}|:9[0-9]{3}')"
IS_LIST="$("$BASE_DIR/wmlist" | grep -oE ': [0-9]+' | sed 's/: /:/')"

PORT_LIST="${SS_LIST} ${IS_LIST}"

IDX=0
while [[ $IDX -lt 444 ]]
do
    if [[ $(grep -c ":${P_PORT}" <<< "$PORT_LIST") -eq 0 ]]
    then
        break
    fi
    P_PORT=$((P_PORT + 1))
    IDX=$((IDX + 1))
done

IDX=0
while [[ $IDX -lt 444 ]]
do
    if [[ $(grep -c ":${D_PORT}" <<< "$PORT_LIST") -eq 0 ]]
    then
        break
    fi
    D_PORT=$((D_PORT + 1))
    IDX=$((IDX + 1))
done

IDX=0
while [[ $IDX -lt 444 ]]
do
    if [[ $(grep -c ":${J_PORT}" <<< "$PORT_LIST") -eq 0 ]]
    then
        break
    fi
    J_PORT=$((J_PORT + 1))
    IDX=$((IDX + 1))
done

"$INST_DIR/is_instance.sh" create \
    -Dinstance.name="$IS_NAME" \
    -Dprimary.port="$P_PORT" \
    -Ddiagnostic.port="$D_PORT" \
    -Djmx.port="$J_PORT" \
    -Dadmin.password=manage
EOF

cat > wmdelete <<'EOF'
#!/bin/bash
#
# ============================================================
# Program name : wmdelete
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

BASE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$BASE_DIR/wm.cnf"

IS_NAME="$1"

if [[ -z "${IS_NAME// }" ]]
then
    echo "Integration server cannot be empty."
    echo "Syntax:"
    echo "    wmdelete <integrationServerName>"
    echo
    echo "Correct and reissue the command."
    exit 1
fi

"$INST_DIR/is_instance.sh" delete \
    -Dinstance.name="$IS_NAME"
EOF

cat > wmlist <<'EOF'
#!/bin/bash
#
# ============================================================
# Program name : wmlist
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

BASE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$BASE_DIR/wm.cnf"

JSON=0
if [[ "$1" == "--json" ]]
then
    JSON=1
fi


json_out="[" first=1
for IS in "$INST_DIR"/*; do
    [[ -d "$IS" && -x "$IS/bin/sagis111" ]] || continue
    NAME=$(basename "$IS")

    "$IS/bin/sagis111" status >/dev/null 2>&1
    RUNNING=$?
    STATE="STOPPED"

    if [[ RUNNING -eq 0 ]]
    then
        STATE="STARTED"
    fi

    CONF="$IS/config/server.cnf"
    WRAP="$IS/configuration/custom_wrapper.conf"

    P=$(grep watt.server.port= "$CONF" 2>/dev/null | cut -d= -f2)
    D=$(grep watt.server.diagnostic.port= "$CONF" 2>/dev/null | cut -d= -f2)
    J=$(grep jmxremote.port= "$WRAP" 2>/dev/null | sed 's/.*=//')

    if (( JSON )); then
        [[ $first -eq 0 ]] && json_out+=","
        first=0
        json_out+="{\"name\":\"$NAME\",\"state\":\"${STATE}\""
        json_out+=",\"primary_port\":\"${P:-}\""
        json_out+=",\"diagnostic_port\":\"${D:-}\""
        json_out+=",\"jmx_port\":\"${J:-}\"}"
    else
        echo "---"
        "$IS/bin/sagis111" status
        printf "%20s: %s\n" "JMX Port" "${J:-Not Set}"
        printf "%20s: %s\n" "Primary Port" "${P:-Not Set}"
        printf "%20s: %s\n" "Diagnostic Port" "${D:-Not Set}"
    fi
done

(( JSON )) && echo "$json_out]"
EOF

for cmd in start stop; do
cat > wm$cmd <<EOF
#!/bin/bash
#
# ============================================================
# Program name : wm$cmd
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

BASE_DIR=\$(dirname "\$(readlink -f "\${BASH_SOURCE[0]}")")
source "\$BASE_DIR/wm.cnf"

IS_NAME="\$1"

if [[ -z "\${IS_NAME// }" ]]
then
    echo "Integration server cannot be empty."
    echo "Syntax:"
    echo "    wm$cmd <integrationServerName>"
    echo
    echo "Correct and reissue the command."
    exit 1
fi

if [[ ! -d "\${INST_DIR}/\${IS_NAME}" ]]
then
    echo "Integration Server '\${IS_NAME}' does not exists."
    echo "An integration server can be used only if it has already been created."
    echo "No user action required."
    exit 2
fi

"\$INST_DIR/\$IS_NAME/bin/sagis111" $cmd
EOF
done

cat > wmservice <<'EOF'
#!/bin/bash
#
# ============================================================
# Program name : wmlist
# Author       : Arson Marianus
# Website      : https://dev.bitsbyste.id
# GitHub       : https://github.com/m-arson
# License      : Copyleft (ↄ) GPL v3 or later
# ============================================================

BASE_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
source "$BASE_DIR/wm.cnf"


cd $BASE_DIR/..

echo
echo " IBM WebMethods Installation Inventory"
echo
echo " Home Directory       : $PWD"
echo " JDK  version         : $(./jvm/jvm/bin/java -version 2>&1 | head -n1 | awk '{print $3}' | tr -d '\"')"
echo " Hostname             : $HOSTNAME"
echo " Machine Type         : $(uname -m)"
echo " Kernel Version       : $(uname -r)"
echo " WmAdmin Tool Version : 1.1.4"
echo " Author               : Arson Marianus"
echo " GitHub               : https://github.com/m-arson/wmadmin-tool/"
echo
echo "-----------------------------------------------------------------------------------------------------"
printf " %-30s %-60s %s\n" "Package" "Product Name" "Version"
echo "-----------------------------------------------------------------------------------------------------"

for package in $(find . -type f -iname "*swidtag*" | awk -F "/" '{print $2}' | uniq | sort -V)
do
    for sw in $(find ./$package -type f -iname "*swidtag*" | sort -V)
    do
        product_name=$(cat $sw | grep '<SoftwareIdentity' | grep -oE 'name="[a-zA-Z0-9 ]+"' | sed 's/name="//' | tr -d '"')
        product_version=$(cat $sw | grep '<SoftwareIdentity' | grep -oE 'version="[a-zA-Z0-9 \.]+"' | sed 's/version="//' | tr -d '"')
        printf " %-30s %-60s %s\n" "$package" "$product_name" "$product_version"
    done
done
EOF

chmod +x wmcreate wmdelete wmlist wmstart wmstop wmservice

need_root
for f in wmcreate wmdelete wmlist wmstart wmstop wmservice; do
    ln -sf "$ADDONS_DIR/$f" "$BIN_DIR/$f"
done

echo "[SUCCESS] wm admin tools installed"
