#!/system/bin/sh

SCRIPT_SELF=$(readlink -f "$0" 2>/dev/null)
[ -z "$SCRIPT_SELF" ] && SCRIPT_SELF="$0"
MODDIR=$(dirname "$SCRIPT_SELF")
CONFIG_FILE="$MODDIR/配置文件.txt"
LIST_FILE="$MODDIR/黑白名单.txt"
LOG_FILE="$MODDIR/日志.log"
STATS_FILE="$MODDIR/压制统计.txt"
MODULE_PROP="$MODDIR/module.prop"
CACHE_TOTAL_KILL=0

check_daemon_running() {
    for _p in /proc/[0-9]*; do
        [ -d "$_p" ] || continue
        [ -r "$_p/cmdline" ] || continue
        IFS="" read -r -d '' _c < "$_p/cmdline" 2>/dev/null
        if [ "$_c" = "processkill" ]; then
            _found_pid=${_p##*/}
            if [ "$_found_pid" != "$$" ]; then
                return 0
            fi
        fi
    done
    return 1
}

if [ "$1" != "--daemon" ]; then
    if check_daemon_running; then
        exit 0
    fi
    setsid sh "$SCRIPT_SELF" --daemon >/dev/null 2>&1 &
    exit 0
fi

if [ "$2" != "--renamed" ]; then
    exec -a "processkill" sh "$SCRIPT_SELF" --daemon --renamed
fi

CPU_AFFINITY_MASK=3
TAB=$(printf '\t')
CR=$(printf '\r')

DEFAULT_OOM_THRESHOLD=800
DEFAULT_DEEP_PRESS=0
DEFAULT_POLL_INTERVAL=30
DEFAULT_LOG_MAX_LINES=100
DEFAULT_VERBOSE_KILL_LOG=0
DEFAULT_PROTECT_FOREGROUND=1
DEFAULT_NOTIFY_ENABLE=0

CACHE_OOM_THRESHOLD=""
CACHE_DEEP_PRESS=""
CACHE_POLL_INTERVAL=""
CACHE_LOG_MAX_LINES=""
CACHE_VERBOSE_KILL_LOG=""
CACHE_PROTECT_FOREGROUND=""
CACHE_NOTIFY_ENABLE=""

CACHE_WHITELIST=""
CACHE_BLACKLIST=""
CACHE_LIST_COUNT=0

LOOP_COUNT=0
SELF_PID=$$
MONITOR_PID=""
SLEEP_PID=""

RELOAD_FLAG=0
trap 'RELOAD_FLAG=1; [ -n "$SLEEP_PID" ] && kill -9 "$SLEEP_PID" 2>/dev/null' USR1

log_line() {
    _ts=$(date '+%H:%M:%S' 2>/dev/null)
    [ -n "$_ts" ] || _ts="00:00:00"
    printf '%s %s\n' "$_ts" "$*" >> "$LOG_FILE"
}

trim_and_strip_comment() {
    _s=$1
    _s=${_s%%#*}
    while :; do case "$_s" in " "*) _s=${_s#?} ;; "$TAB"*) _s=${_s#?} ;; "$CR"*) _s=${_s#?} ;; *) break ;; esac; done
    while :; do case "$_s" in *" ") _s=${_s%?} ;; *"$TAB") _s=${_s%?} ;; *"$CR") _s=${_s%?} ;; *) break ;; esac; done
    TRIM_RESULT=$_s
}

is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_int() { case "$1" in ''|-) return 1 ;; -*) is_uint "${1#-}" ;; *) is_uint "$1" ;; esac; }
load_total_kill() {
    CACHE_TOTAL_KILL=0
    [ -f "$STATS_FILE" ] || return 0
    IFS= read -r _n < "$STATS_FILE" 2>/dev/null || _n=0
    is_uint "$_n" && CACHE_TOTAL_KILL=$_n
}

save_total_kill() {
    printf '%s\n' "$CACHE_TOTAL_KILL" > "$STATS_FILE" 2>/dev/null
}

update_module_prop_desc() {
    [ -f "$MODULE_PROP" ] || return 0

    _tmp="$MODULE_PROP.tmp"
    _new_desc="description=智能压制后台进程，进程名为processkill，目前用shell写，会在模块目录下生成日志，刷入后自动正常配置文件和黑白名单，支持实时修改，日志会自动清理，可自行查看｜累计压制:${CACHE_TOTAL_KILL}"

    if grep -q '^description=' "$MODULE_PROP" 2>/dev/null; then
        sed "s/^description=.*/$_new_desc/" "$MODULE_PROP" > "$_tmp" 2>/dev/null || return 1
    else
        cat "$MODULE_PROP" > "$_tmp" 2>/dev/null || return 1
        printf '%s\n' "$_new_desc" >> "$_tmp"
    fi

    mv -f "$_tmp" "$MODULE_PROP" 2>/dev/null
}

create_default_files() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<'EOF'
oom_threshold=800
# 深度压制：1=杀所有符合条件的进程，0=只杀带有冒号的子进程（推荐）
deep_press=0
# 轮询间隔（秒，最低30）
poll_interval=30
# 日志最大行数
log_max_lines=100
# 是否记录每个被杀进程明细：1=开，0=关（建议关，省IO）
verbose_kill_log=0
# 是否保护前台应用：1=保护，0=不保护
protect_foreground=1
# 是否启用通知：1=开，0=关
通知=0
EOF
        chmod 0644 "$CONFIG_FILE"
    fi

    if [ ! -f "$LIST_FILE" ]; then
        cat > "$LIST_FILE" <<'EOF'
# ==========================================
# 黑白名单配置文件
# 正常填写包名代表【白名单】
# 在包名前加 ! 号代表【黑名单】
# 支持通配符：* ? []
# 注意：即使是黑名单，在前台时也会受到保护免杀
# ==========================================

# 白名单示例
com.tencent.mm
com.tencent.mm:push
com.tencent.mobileqq
com.tencent.mobileqq:MSF
com.google.android.webview:sandboxed_process0:org.chromium.content.app.SandboxedProcessService0:*

# 黑名单示例（只要在后台，无视OOM，发现即杀）
#!com.example.badapp(需要去掉#)
EOF
        chmod 0644 "$LIST_FILE"
    fi
    touch "$LOG_FILE" 2>/dev/null
        if [ ! -f "$STATS_FILE" ]; then
        echo 0 > "$STATS_FILE"
        chmod 0644 "$STATS_FILE"
    fi
}

cleanup() {
    [ -n "$MONITOR_PID" ] && kill -9 "$MONITOR_PID" 2>/dev/null
    [ -n "$SLEEP_PID" ] && kill -9 "$SLEEP_PID" 2>/dev/null
}
trap 'cleanup; exit 0' INT TERM EXIT

bind_cpu01() {
    taskset -p "$CPU_AFFINITY_MASK" "$$" >/dev/null 2>&1 || busybox taskset -p "$CPU_AFFINITY_MASK" "$$" >/dev/null 2>&1
}

load_config() {
    _new_oom=$DEFAULT_OOM_THRESHOLD
    _new_deep=$DEFAULT_DEEP_PRESS
    _new_poll=$DEFAULT_POLL_INTERVAL
    _new_log_max=$DEFAULT_LOG_MAX_LINES
    _new_verbose=$DEFAULT_VERBOSE_KILL_LOG
    _new_protect_fg=$DEFAULT_PROTECT_FOREGROUND
    _new_notify=$DEFAULT_NOTIFY_ENABLE

    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r _line || [ -n "$_line" ]; do
            trim_and_strip_comment "$_line"
            _line=$TRIM_RESULT
            [ -n "$_line" ] || continue
            case "$_line" in *=*) ;; *) continue ;; esac

            _key=${_line%%=*}
            _val=${_line#*=}
            trim_and_strip_comment "$_key"; _key=$TRIM_RESULT
            trim_and_strip_comment "$_val"; _val=$TRIM_RESULT

            case "$_key" in
                oom_threshold) is_uint "$_val" && _new_oom=$_val ;;
                deep_press) case "$_val" in 0|1) _new_deep=$_val ;; esac ;;
                poll_interval) is_uint "$_val" && { [ "$_val" -lt 10 ] && _new_poll=10 || _new_poll=$_val; } ;;
                log_max_lines) is_uint "$_val" && [ "$_val" -gt 0 ] && _new_log_max=$_val ;;
                verbose_kill_log) case "$_val" in 0|1) _new_verbose=$_val ;; esac ;;
                protect_foreground) case "$_val" in 0|1) _new_protect_fg=$_val ;; esac ;;
                通知) case "$_val" in 0|1) _new_notify=$_val ;; esac ;;
            esac
        done < "$CONFIG_FILE"
    fi

    CACHE_OOM_THRESHOLD=$_new_oom
    CACHE_DEEP_PRESS=$_new_deep
    CACHE_POLL_INTERVAL=$_new_poll
    CACHE_LOG_MAX_LINES=$_new_log_max
    CACHE_VERBOSE_KILL_LOG=$_new_verbose
    CACHE_PROTECT_FOREGROUND=$_new_protect_fg
    CACHE_NOTIFY_ENABLE=$_new_notify
}

load_list() {
    _new_white=""
    _new_black=""
    _count=0

    if [ -f "$LIST_FILE" ]; then
        while IFS= read -r _line || [ -n "$_line" ]; do
            trim_and_strip_comment "$_line"
            _line=$TRIM_RESULT
            [ -n "$_line" ] || continue

            if [ "${_line#!}" != "$_line" ]; then
                _item=${_line#!}
                [ -z "$_new_black" ] && _new_black=$_item || _new_black="$_new_black
$_item"
            else
                [ -z "$_new_white" ] && _new_white=$_line || _new_white="$_new_white
$_line"
            fi
            _count=$((_count + 1))
        done < "$LIST_FILE"
    fi

    CACHE_WHITELIST=$_new_white
    CACHE_BLACKLIST=$_new_black
    CACHE_LIST_COUNT=$_count
}

match_in_list() {
    _cmd="$1"
    _list="$2"
    [ -n "$_list" ] || return 1

    OLD_IFS=$IFS
    IFS='
'
    for _rule in $_list; do
        [ -n "$_rule" ] || continue
        case "$_cmd" in
            $_rule) IFS=$OLD_IFS; return 0 ;;
        esac
    done
    IFS=$OLD_IFS
    return 1
}

is_whitelisted() { match_in_list "$1" "$CACHE_WHITELIST"; }
is_blacklisted() { match_in_list "$1" "$CACHE_BLACKLIST"; }

get_foreground_app() {
    GET_FOREGROUND_RESULT=""
    [ "$CACHE_PROTECT_FOREGROUND" = "1" ] || return 1

    GET_FOREGROUND_RESULT=$(dumpsys window windows 2>/dev/null | sed -n '
/mCurrentFocus/{s/.* u[0-9][0-9]* \([A-Za-z0-9._:-][A-Za-z0-9._:-]*\)\/.*/\1/p;q}
/mFocusedApp/{s/.* \([A-Za-z0-9._:-][A-Za-z0-9._:-]*\)\/.*/\1/p;q}')
    [ -n "$GET_FOREGROUND_RESULT" ] && return 0

    GET_FOREGROUND_RESULT=$(dumpsys activity recents 2>/dev/null | sed -n '
/Recent #0/{s/.*A=[0-9][0-9]*:\([A-Za-z0-9._:-]*\).*/\1/p;q}')
    [ -n "$GET_FOREGROUND_RESULT" ]
}

trim_log_if_needed() {
    if [ $((LOOP_COUNT % 10)) -ne 0 ]; then return 0; fi
    [ -f "$LOG_FILE" ] || return 0

    _tmp="$LOG_FILE.tmp"
    tail -n "$CACHE_LOG_MAX_LINES" "$LOG_FILE" > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
    if [ -s "$_tmp" ]; then mv -f "$_tmp" "$LOG_FILE"; else rm -f "$_tmp" 2>/dev/null; fi
}

do_press() {
    _start_time=$(date '+%H:%M:%S' 2>/dev/null)
    _start_epoch=$(date '+%s' 2>/dev/null)
    [ -n "$_start_time" ] || _start_time="00:00:00"
    [ -n "$_start_epoch" ] || _start_epoch=0

    get_foreground_app
    _foreground_app=$GET_FOREGROUND_RESULT

    _kill_success=0; _kill_black=0; _kill_fail=0
    _skip_whitelist=0; _skip_foreground=0; _candidate_count=0
    _detail=""

    for _proc in /proc/[0-9]*; do
        [ -d "$_proc" ] || continue
        _pid=${_proc##*/}
        [ "$_pid" = "$SELF_PID" ] && continue

        [ -r "$_proc/cmdline" ] || continue
        IFS="" read -r -d '' _cmd < "$_proc/cmdline" 2>/dev/null
        [ -n "$_cmd" ] || continue

        _is_fg=0
        if [ -n "$_foreground_app" ]; then
            if [ "$_cmd" = "$_foreground_app" ]; then
                _is_fg=1
            else
                case "$_cmd" in "$_foreground_app":*) _is_fg=1 ;; esac
            fi
        fi

        if [ "$_is_fg" = "1" ]; then
            _skip_foreground=$((_skip_foreground + 1))
            continue
        fi

        if is_blacklisted "$_cmd"; then
            if kill -9 "$_pid" 2>/dev/null; then
                _kill_black=$((_kill_black + 1))
                [ "$CACHE_VERBOSE_KILL_LOG" = "1" ] && _detail="${_detail}[黑名强杀] PID:$_pid CMD:$_cmd\n"
            fi
            continue
        fi

        [ -r "$_proc/oom_score_adj" ] || continue
        IFS= read -r _oom_adj < "$_proc/oom_score_adj" 2>/dev/null || continue
        is_int "$_oom_adj" || continue

        _cpuset=""
        [ -r "$_proc/cpuset" ] && IFS= read -r _cpuset < "$_proc/cpuset" 2>/dev/null

        _is_bg_low_oom=0
        if [ "$_oom_adj" -lt "$CACHE_OOM_THRESHOLD" ]; then
            case "$_cpuset" in */background*) _is_bg_low_oom=1 ;; esac
        fi

        if [ "$_is_bg_low_oom" = "0" ] && [ "$_oom_adj" -lt "$CACHE_OOM_THRESHOLD" ]; then
            continue
        fi

        if is_whitelisted "$_cmd"; then
            _skip_whitelist=$((_skip_whitelist + 1))
            continue
        fi

        if [ "$CACHE_DEEP_PRESS" != "1" ]; then
            case "$_cmd" in *:*) ;; *) continue ;; esac
        fi

        _candidate_count=$((_candidate_count + 1))

        if kill -9 "$_pid" 2>/dev/null; then
            _kill_success=$((_kill_success + 1))
            if [ "$CACHE_VERBOSE_KILL_LOG" = "1" ]; then
                if [ "$_is_bg_low_oom" = "1" ]; then
                    _detail="${_detail}[限制后台] PID:$_pid CMD:$_cmd OOM:$_oom_adj\n"
                else
                    _detail="${_detail}[常规阈值] PID:$_pid CMD:$_cmd OOM:$_oom_adj\n"
                fi
            fi
        else
            _kill_fail=$((_kill_fail + 1))
        fi
    done

    _end_time=$(date '+%H:%M:%S' 2>/dev/null)
    _end_epoch=$(date '+%s' 2>/dev/null)
    [ -n "$_end_time" ] || _end_time="00:00:00"
    [ -n "$_end_epoch" ] || _end_epoch=$_start_epoch
    _duration=$((_end_epoch - _start_epoch))

    {
        printf '%s === 检查 | 前台:%s | OOM:%s | 间隔:%ss\n' "$_start_time" "${_foreground_app:-无}" "$CACHE_OOM_THRESHOLD" "$CACHE_POLL_INTERVAL"
        printf '%s === 结束 | 黑杀:%s | 常规(含限制后台):%s | 白免:%s | 前台免:%s | 耗时:%ss\n' "$_end_time" "$_kill_black" "$_kill_success" "$_skip_whitelist" "$_skip_foreground" "$_duration"
        if [ "$CACHE_VERBOSE_KILL_LOG" = "1" ] && [ -n "$_detail" ]; then
            printf '%b' "$_detail"
        fi
    } >> "$LOG_FILE"
        _round_kill=$((_kill_black + _kill_success))
    if [ "$_round_kill" -gt 0 ]; then
        CACHE_TOTAL_KILL=$((CACHE_TOTAL_KILL + _round_kill))
        save_total_kill
    fi

    update_module_prop_desc
}

start_file_monitor() {
    _last_m=""
    while :; do
        sleep 2
        _m1=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
        _m2=$(stat -c %Y "$LIST_FILE" 2>/dev/null || echo "0")
        _curr_m="${_m1}_${_m2}"

        if [ -z "$_last_m" ]; then
            _last_m=$_curr_m
        elif [ "$_curr_m" != "$_last_m" ]; then
            _last_m=$_curr_m
            kill -USR1 "$SELF_PID" 2>/dev/null
        fi
    done
}

wait_boot_completed() {
    while :; do
        _boot=$(getprop sys.boot_completed 2>/dev/null)
        [ "$_boot" = "1" ] && break
        sleep 5
    done
    sleep 10
}

main_loop() {
    wait_boot_completed
    create_default_files
    bind_cpu01
    load_config
    load_list
    load_total_kill
    update_module_prop_desc

    if [ "$CACHE_NOTIFY_ENABLE" = "1" ]; then
        sh "$MODDIR/action2.sh" &
    fi

    log_line "processkill 已启动，等待30秒后开始"
    sleep 30

    start_file_monitor &
    MONITOR_PID=$!

    while :; do
        _is_reload=0

        if [ "$RELOAD_FLAG" = "1" ]; then
            load_config
            load_list
            RELOAD_FLAG=0
            _is_reload=1
            log_line "检测到配置修改，已重载，跳过本轮压制"
        fi

        if [ "$_is_reload" = "0" ]; then
            do_press
            LOOP_COUNT=$((LOOP_COUNT + 1))
            trim_log_if_needed
        fi

        sleep "$CACHE_POLL_INTERVAL" &
        SLEEP_PID=$!
        wait $SLEEP_PID
    done
}

main_loop
