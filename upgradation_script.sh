#!/bin/bash

####################################
# RHEL CHECK
####################################
if ! grep -qi "rhel\|red hat" /etc/os-release; then
  echo "❌ This script is for RHEL only"
  exit 1
fi

####################################
# VARIABLES
####################################
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
BASE=/tmp/rhel

INFO="$BASE/system_info"
IMAGES="$BASE/images"
CONTAINERS="$BASE/containers"
ZIPS="$BASE/zips"
CHECKLIST="$BASE/CHECKLIST.txt"

FAIL=0
mkdir -p "$INFO" "$IMAGES" "$CONTAINERS" "$ZIPS"

####################################
# CHECKLIST HELPERS
####################################
pass() { echo "✅ PASS - $1" | tee -a "$CHECKLIST"; }
fail() { echo "❌ FAIL - $1" | tee -a "$CHECKLIST"; FAIL=1; }

####################################
# SYSTEM INFO
####################################
df -h > "$INFO/disk_space.txt"
free -h > "$INFO/ram.txt"
lscpu > "$INFO/cpu.txt"
ip a > "$INFO/ip_address.txt"
route -n > "$INFO/routes.txt"
uname -a > "$INFO/uname.txt"
cat /etc/os-release > "$INFO/os_release.txt"
cat /etc/hosts > "$INFO/hosts.txt"
crontab -l > "$INFO/crontab.txt" 2>/dev/null || echo "(no crontab)" > "$INFO/crontab.txt"

####################################
# ROOT SYSTEM INFO (DIRECT)
####################################
lsblk > "$INFO/lsblk.txt" 2>/dev/null
mount > "$INFO/mounts.txt" 2>/dev/null
cat /etc/fstab > "$INFO/fstab.txt" 2>/dev/null
systemctl list-units --type=service --state=running > "$INFO/running_services.txt" 2>/dev/null
rpm -qa > "$INFO/installed_packages.txt" 2>/dev/null
netstat -tunlp > "$INFO/netstat.txt" 2>/dev/null
# firewall-cmd --list-all > "$INFO/firewalld.txt" 2>/dev/null

####################################
# DOCKER INFO
####################################
if command -v docker >/dev/null 2>&1; then
  docker ps -a > "$CONTAINERS/container_list.txt"

docker ps -a --format "{{.Names}}" | while read -r c; do
    [[ -z "$c" ]] && continue
    docker inspect "$c" > "$CONTAINERS/${c}_inspect.json"
  done

 docker images > "$IMAGES/image_list.txt"
echo "Saving images..."
 docker images --format "{{.Repository}}:{{.Tag}}" | while read -r img; do
    SAFE=$(echo "$img" | tr '/:' '_')
 docker save -o "$IMAGES/${SAFE}.tar" "$img"
  done
fi

####################################
# CRONTAB SCRIPT EXTRACTION
####################################
CRONTB_DIR="$BASE/crontb"
mkdir -p "$CRONTB_DIR"

echo "📅 Extracting scripts from crontab..."

crontab -l > "$INFO/crontab.txt" 2>/dev/null || {
  echo "(no crontab)" > "$INFO/crontab.txt"
  exit 0
}

grep -v '^[[:space:]]*#' "$INFO/crontab.txt" | \
grep -oE '/[^[:space:]]+\.sh' | \
sort -u | while read -r SCRIPT; do
  if [[ -f "$SCRIPT" ]]; then
    cp -a "$SCRIPT" "$CRONTB_DIR/"
    echo "✅ Saved cron script: $SCRIPT"
  else
    echo "⚠️  Script referenced but not found: $SCRIPT"
  fi
done

####################################
# DIRECTORIES TO ZIP
####################################
echo
echo "📦 Enter directories to ZIP (type 'done' when finished):"

while true; do
  read -rp "Directory: " DIR
  [[ -z "$DIR" ]] && continue
  [[ "$DIR" == "done" ]] && break

  if [[ -d "$DIR" ]]; then
    P=$(dirname "$DIR")
    N=$(basename "$DIR")
    ( cd "$P" && zip -r "$ZIPS/${N}_$DATE_TAG.zip" "$N" >/dev/null 2>&1 )
    echo "✅ Zipped directory: $DIR"
  else
    echo "⚠️  Not a directory, skipped"
  fi
done

####################################
# FILES TO SAVE
####################################
echo
echo "📄 Enter files to SAVE (type 'done' when finished):"

while true; do
  read -rp "File: " FILE
  [[ -z "$FILE" ]] && continue
  [[ "$FILE" == "done" ]] && break

  if [[ -f "$FILE" ]]; then
    cp -a "$FILE" "$IMAGES/"
    echo "✅ Saved file: $FILE"
  else
    echo "⚠️  File not found, skipped"
  fi
done

####################################
# CHECKLIST
####################################
echo "=========== CHECKLIST ===========" | tee "$CHECKLIST"

[[ -s "$INFO/disk_space.txt" ]] && pass "Disk space captured" || fail "Disk space missing"
[[ -s "$INFO/ram.txt" ]] && pass "RAM captured" || fail "RAM missing"
[[ -s "$INFO/cpu.txt" ]] && pass "CPU captured" || fail "CPU missing"
[[ -s "$INFO/ip_address.txt" ]] && pass "IP captured" || fail "IP missing"
[[ -s "$INFO/routes.txt" ]] && pass "Routes captured" || fail "Routes missing"
[[ -s "$INFO/uname.txt" ]] && pass "Kernel info captured" || fail "Kernel info missing"
[[ -s "$INFO/os_release.txt" ]] && pass "OS info captured" || fail "OS info missing"
[[ -s "$INFO/hosts.txt" ]] && pass "/etc/hosts captured" || fail "/etc/hosts missing"
[[ -s "$INFO/crontab.txt" ]] && pass "Crontab captured" || fail "Crontab missing"

[[ -s "$INFO/lsblk.txt" ]] && pass "Block devices captured" || fail "Block devices missing"
[[ -s "$INFO/mounts.txt" ]] && pass "Mounts captured" || fail "Mounts missing"
[[ -s "$INFO/fstab.txt" ]] && pass "fstab captured" || fail "fstab missing"
[[ -s "$INFO/running_services.txt" ]] && pass "Running services captured" || fail "Running services missing"
[[ -s "$INFO/installed_packages.txt" ]] && pass "Installed packages captured" || fail "Installed packages missing"

IMG_CNT=$(ls "$IMAGES"/*.tar 2>/dev/null | wc -l)
[[ "$IMG_CNT" -gt 0 ]] && pass "Images saved ($IMG_CNT)" || fail "No images saved"

####################################
# FINAL
####################################
echo "================================" | tee -a "$CHECKLIST"
[[ "$FAIL" -eq 0 ]] && echo "✅ BACKUP COMPLETED SUCCESSFULLY" | tee -a "$CHECKLIST" \
                   || echo "❌ BACKUP INCOMPLETE" | tee -a "$CHECKLIST"

echo "📁 Backup location: $BASE"


