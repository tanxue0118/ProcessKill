#!/system/bin/sh

MODDIR=${0%/*}
MAIN_SCRIPT="$MODDIR/processkill.sh"
CONFIG_FILE="$MODDIR/配置文件.txt"
WHITELIST_FILE="$MODDIR/黑白名单.txt"
LOG_FILE="$MODDIR/日志.log"

[ -f "$MAIN_SCRIPT" ] || exit 0

chmod 0755 "$MAIN_SCRIPT" 2>/dev/null
chmod 0755 "$MODDIR/action2.sh" 2>/dev/null
[ -f "$CONFIG_FILE" ] && chmod 0644 "$CONFIG_FILE" 2>/dev/null
[ -f "$WHITELIST_FILE" ] && chmod 0644 "$WHITELIST_FILE" 2>/dev/null

touch "$LOG_FILE" 2>/dev/null
chmod 0644 "$LOG_FILE" 2>/dev/null

echo "$(date '+%H:%M:%S') service.sh 拉起 processkill" >> "$LOG_FILE"

sleep 180

sh "$MAIN_SCRIPT" &
sh "$MODDIR/action2.sh" &

exit 0