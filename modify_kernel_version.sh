#!/usr/bin/env bash
#
# 修改 OpenWrt target 的内核版本 (KERNEL_PATCHVER)
# Usage: ./modify_kernel_version.sh <target> <version>
# Example: ./modify_kernel_version.sh rockchip 6.6
#

TARGET=$1
KERNEL_VERSION=$2

if [ -z "$TARGET" ] || [ -z "$KERNEL_VERSION" ]; then
    echo "用法: $0 <target> <kernel_version>"
    echo "示例: $0 rockchip 6.6"
    exit 1
fi

# BASE_PATH=$(cd $(dirname $0) && pwd)
# OPENWRT_PATH="$BASE_PATH/../lede" # assuming lede is the openwrt dir
OPENWRT_PATH=$(pwd) # assuming lede is the openwrt dir

if [ ! -d "$OPENWRT_PATH" ]; then
    echo "错误: 未找到 OpenWrt 源码目录: $OPENWRT_PATH"
    exit 1
fi

# 尝试寻找包含 KERNEL_PATCHVER 定义的 Makefile
# 支持路径回溯，例如输入 qualcommax/ipq60xx 时，可以自动找到 qualcommax/Makefile

SEARCH_DIR="$OPENWRT_PATH/target/linux/$TARGET"
TARGET_MAKEFILE=""

# 如果用户输入的是纯名称（如 ipq60xx），但该目录不存在于 target/linux 下，
# 则尝试在所有 target 中搜索该子目标 (可选功能，防止用户只知道子目标名)
if [ ! -d "$SEARCH_DIR" ]; then
    # 简单的搜索：看是否有同名的目录存在于某个 target 下
    FOUND_PATH=$(find "$OPENWRT_PATH/target/linux" -mindepth 2 -maxdepth 2 -type d -name "$TARGET" | head -n 1)
    if [ -n "$FOUND_PATH" ]; then
        SEARCH_DIR="$FOUND_PATH"
        echo "推测目标路径为: $SEARCH_DIR"
    fi
fi

# 开始回溯查找 Makefile
CURRENT_DIR="$SEARCH_DIR"
LINUX_ROOT="$OPENWRT_PATH/target/linux"

while [[ "$CURRENT_DIR" == "$LINUX_ROOT"* ]]; do
    if [ -f "$CURRENT_DIR/Makefile" ]; then
        if grep -q "^KERNEL_PATCHVER" "$CURRENT_DIR/Makefile"; then
            TARGET_MAKEFILE="$CURRENT_DIR/Makefile"
            echo "找到定义 KERNEL_PATCHVER 的 Makefile: $TARGET_MAKEFILE"
            break
        fi
    fi
    
    # 向上一级
    if [ "$CURRENT_DIR" == "$LINUX_ROOT" ]; then 
        break 
    fi
    CURRENT_DIR=$(dirname "$CURRENT_DIR")
done


if [ -z "$TARGET_MAKEFILE" ]; then
    echo "错误: 在 $TARGET 或其父目录中未找到定义 KERNEL_PATCHVER 的 Makefile"
    echo "请确认 target 名称路径是否正确"
    exit 1
fi

echo "正在将内核版本修改为 $KERNEL_VERSION ..."

# 检查当前文件中是否有 KERNEL_PATCHVER 定义
if grep -q "^KERNEL_PATCHVER" "$TARGET_MAKEFILE"; then
    # 使用 sed 修改，兼容可能有空格的情况
    sed -i "s/^KERNEL_PATCHVER[[:space:]]*:=.*/KERNEL_PATCHVER:=$KERNEL_VERSION/" "$TARGET_MAKEFILE"
    echo "成功修改 $TARGET/Makefile 中的 KERNEL_PATCHVER 为 $KERNEL_VERSION"
else
    echo "错误: 在 $TARGET_MAKEFILE 中未找到 KERNEL_PATCHVER 变量"
    exit 1
fi

# 检查是否存在对应的 config 文件或 patches 目录 (作为警告)
CONFIG_FILE="$OPENWRT_PATH/target/linux/$TARGET/config-$KERNEL_VERSION"
GENERIC_CONFIG="$OPENWRT_PATH/target/linux/generic/config-$KERNEL_VERSION"

if [ ! -f "$CONFIG_FILE" ] && [ ! -f "$GENERIC_CONFIG" ]; then
    echo "警告: 未找到对应的内核配置文件 (config-$KERNEL_VERSION)"
    echo "请检查该版本是否被当前源码支持。"
fi

echo "完成。"
