for PKG in "bin.mt.plus.canary" "bin.mt.plus"; do
    am start -n "$PKG/bin.mt.plus.Main" -d "file:///data/adb/modules/Process_Kill" 2>/dev/null && exit 0
done
