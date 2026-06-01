SKIPUNZIP=0

ui_print "=================================="
ui_print "Processkill 进程压制模块"
ui_print "=================================="
ui_print " "

ui_print "- 正在配置模块文件"
chmod 0755 "$MODPATH/service.sh"
chmod 0755 "$MODPATH/processkill.sh"
chmod 0644 "$MODPATH/module.prop"

inherit_config() {
    OLD_MODDIR="/data/adb/modules/Process_Kill"
    NEW_MODDIR="$MODPATH"

    ui_print " "
    ui_print "╔══════════════════════════════════════╗"
    ui_print "║          配置文件检查与继承          ║"
    ui_print "╚══════════════════════════════════════╝"

    if [ ! -d "$OLD_MODDIR" ]; then
        ui_print "ℹ️ 未检测到旧模块目录"
        ui_print "✅ 将使用模块自带默认配置"
        return 0
    fi

    inherited=0

    if [ -f "$OLD_MODDIR/黑白名单.txt" ]; then
        cp -af "$OLD_MODDIR/黑白名单.txt" "$NEW_MODDIR/" 2>/dev/null
        ui_print "✅ 已继承：黑白名单.txt"
        ui_print "📝 正在强制写入新内容"
        sed -i '/# 白名单示例/a\com.google.android.webview:sandboxed_process0:org.chromium.content.app.SandboxedProcessService0:*' "$NEW_MODDIR/黑白名单.txt"

        inherited=1
    else
        ui_print "📝 未找到旧版 黑白名单.txt，使用默认配置"
    fi

    if [ -f "$OLD_MODDIR/配置文件.txt" ]; then
        cp -af "$OLD_MODDIR/配置文件.txt" "$NEW_MODDIR/" 2>/dev/null
        ui_print "✅ 已继承：配置文件.txt"
        ui_print "📝 正在强制写入新内容"

        
        echo "# 是否启用通知：1=开，0=关" >> "$NEW_MODDIR/配置文件.txt"
        echo "通知=1" >> "$NEW_MODDIR/配置文件.txt"

        inherited=1
    else
        ui_print "📝 未找到旧版 配置文件.txt，使用默认配置"
    fi

    if [ "$inherited" -eq 0 ]; then
        ui_print "✅ 没有可继承的配置，已使用模块内置默认配置"
    else
        ui_print "🎉 配置文件继承完成"
    fi
}

inherit_config

ui_print " "
ui_print "✅ 模块刷入完成！"
ui_print "请重启手机生效"
ui_print "=================================="

ui_print "🔄 正在跳转酷安主页..."
(am start -d 'coolmarket://u/29109774' >/dev/null 2>&1) &
ui_print "❤️ 感谢您的支持！"
