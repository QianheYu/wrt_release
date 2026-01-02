#!/bin/bash

# 脚本功能：修改 OpenWrt 编译时的默认设置
# 使用方法：
# 1. 交互模式：bash modify_defaults.sh
# 2. 自动模式：bash modify_defaults.sh -y (使用脚本内的预设值)
# 在编译前（feeds update/install 之后）运行此脚本

# --- 用户配置区域 ---
# 设置默认 LAN IP 地址 (留空则不修改)
NEW_IP=""

# 设置默认主机名 (留空则不修改)
NEW_HOSTNAME=""

# 设置默认主题 (确保该主题包已被选中编译，例如 luci-theme-bootstrap) (留空则不修改)
NEW_THEME=""
# ---------------------

# 检查是否有命令行参数（例如 -y）
if [ -n "$1" ]; then
    echo "检测到命令行参数，将使用脚本预设配置自动执行..."
else
    # 无参数，进入交互模式
    echo "=== 进入交互配置模式 (直接回车确认预设值，输入 n 跳过) ==="

    # 1. 设置 LAN IP
    read -p "请输入默认 LAN IP [预设: ${NEW_IP:-跳过}]: " input_ip
    if [ "$input_ip" = "n" ]; then
        NEW_IP=""
    elif [ -n "$input_ip" ]; then
        NEW_IP="$input_ip"
    fi

    # 2. 设置主机名
    CONFIG_GENERATE="package/base-files/files/bin/config_generate"
    if [ -f "$CONFIG_GENERATE" ]; then
        # 尝试提取当前主机名
        CURRENT_HOSTNAME=$(grep "hostname=" "$CONFIG_GENERATE" | head -n 1 | cut -d"'" -f2)
        if [ -n "$CURRENT_HOSTNAME" ]; then
             echo "当前默认主机名: $CURRENT_HOSTNAME"
        fi
    fi
    read -p "请输入默认主机名 [预设: ${NEW_HOSTNAME:-跳过}]: " input_hostname
    if [ "$input_hostname" = "n" ]; then
        NEW_HOSTNAME=""
    elif [ -n "$input_hostname" ]; then
        NEW_HOSTNAME="$input_hostname"
    fi

    # 3. 设置主题
    echo "------------------------------------------------"
    THEMES_DIR="feeds/luci/themes"
    if [ -d "$THEMES_DIR" ]; then
        # 获取主题列表
        available_themes=($(ls "$THEMES_DIR" | grep "luci-theme-"))
        
        if [ ${#available_themes[@]} -gt 0 ]; then
            echo "发现以下可用主题："
            for i in "${!available_themes[@]}"; do
                echo "$((i+1)). ${available_themes[$i]}"
            done
            echo "------------------------------------------------"
            
            read -p "请选择默认主题 (输入序号或名称) [预设: ${NEW_THEME:-跳过}]: " input_theme
            
            # 判断输入是否为数字
            if [[ "$input_theme" =~ ^[0-9]+$ ]]; then
                index=$((input_theme-1))
                if [ $index -ge 0 ] && [ $index -lt ${#available_themes[@]} ]; then
                    NEW_THEME="${available_themes[$index]}"
                    echo "已选择主题: $NEW_THEME"
                else
                    echo "无效序号，保持预设: $NEW_THEME"
                fi
            elif [ "$input_theme" = "n" ]; then
                NEW_THEME=""
            elif [ -n "$input_theme" ]; then
                NEW_THEME="$input_theme"
            fi
        else
             echo "未找到任何主题包，请手动输入。"
             read -p "请输入默认主题 [预设: ${NEW_THEME:-跳过}]: " input_theme
             if [ "$input_theme" = "n" ]; then
                NEW_THEME=""
             elif [ -n "$input_theme" ]; then
                NEW_THEME="$input_theme"
             fi
        fi
    else
        echo "警告: 未找到主题目录 $THEMES_DIR (可能未更新 feeds)"
        read -p "请输入默认主题 [预设: ${NEW_THEME:-跳过}]: " input_theme
        if [ "$input_theme" = "n" ]; then
            NEW_THEME=""
        elif [ -n "$input_theme" ]; then
            NEW_THEME="$input_theme"
        fi
    fi
    
    echo "=== 配置完成，开始执行修改 ==="
fi

echo "开始修改默认设置..."

# 1. 修改默认 LAN IP
# 目标文件: package/base-files/files/bin/config_generate
CONFIG_GENERATE="package/base-files/files/bin/config_generate"
if [ -n "$NEW_IP" ]; then
    if [ -f "$CONFIG_GENERATE" ]; then
        echo "修改默认 LAN IP 为 $NEW_IP"
        # 替换默认的 192.168.1.1
        sed -i "s/192.168.1.1/$NEW_IP/g" "$CONFIG_GENERATE"
    else
        echo "错误: 未找到文件 $CONFIG_GENERATE"
    fi
else
    echo "跳过默认 LAN IP 修改"
fi

# 2. 修改默认主机名
# 目标文件: package/base-files/files/bin/config_generate
if [ -n "$NEW_HOSTNAME" ]; then
    if [ -f "$CONFIG_GENERATE" ]; then
        echo "修改默认主机名为 $NEW_HOSTNAME"
        # 替换 hostname='OpenWrt'
        sed -i "s/hostname='OpenWrt'/hostname='$NEW_HOSTNAME'/g" "$CONFIG_GENERATE"
    else
        echo "错误: 未找到文件 $CONFIG_GENERATE"
    fi
else
    echo "跳过默认主机名修改"
fi

# 3. 修改默认主题
# 目标文件: feeds/luci/collections/luci/Makefile
LUCI_MAKEFILE="feeds/luci/collections/luci/Makefile"
if [ -n "$NEW_THEME" ]; then
    if [ -f "$LUCI_MAKEFILE" ]; then
        echo "修改默认主题为 $NEW_THEME"
        # 将默认的 luci-theme-bootstrap 替换为新主题
        sed -i "s/luci-theme-bootstrap/$NEW_THEME/g" "$LUCI_MAKEFILE"
    else
        echo "错误: 未找到文件 $LUCI_MAKEFILE"
    fi
else
    echo "跳过默认主题修改"
fi

echo "默认设置修改完成！"
