#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/配置文件.txt"

# 读取配置里的 通知=1 或 0
NOTIFY_ENABLE=0
if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r' | cut -d'#' -f1 | xargs)
        [ -z "$line" ] && continue
        case "$line" in
            通知=*) NOTIFY_ENABLE=${line#*=} ;;
        esac
    done < "$CONFIG_FILE"
fi

[ "$NOTIFY_ENABLE" != "1" ] && exit 0

# 后台发通知（兼容 Android 12/13/14/15）
{
    su 2000 -c "cmd notification post -S messaging \
        --conversation 'ProcessKill' \
        --message 'ProcessKill:processkill进程已被拉起' \
        'Tag' '$RANDOM'" >/dev/null 2>&1
        
        sleep 15
        
        su 2000 -c "cmd notification post -S messaging \
        --conversation 'ProcessKill' \
        --message 'ProcessKill:processkill将在30秒后运行' \
        'Tag' '$RANDOM'" >/dev/null 2>&1
        
        sleep 30
        
   PROCESS_NAME="processkill"     
   IS_RUNNING=false
   pidof "$PROCESS_NAME" >/dev/null 2>&1 && IS_RUNNING=true
   if [ "$IS_RUNNING" = true ]; then
     TITLE="ProcessKill"
     TEXT="✅ 进程正在运行"
   else
     TITLE="ProcessKill"
     TEXT="❌ 进程未运行或已异常退出"
   fi
   
   su 2000 -c "cmd notification post -S messaging \
        --conversation 'ProcessKill' \
        --message '$TITLE:$TEXT' \
        'Tag' '$RANDOM'" >/dev/null 2>&1
        
} &

exit 0
