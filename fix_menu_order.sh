#!/bin/bash

# 脚本名称: fix_menu_order.sh
# 功能: 根据配置文件批量修改 OpenWrt 软件包的菜单排序 (Order)
# 用法: ./fix_menu_order.sh [-f config_file] [feeds_dir]
#
# 配置文件格式支持:
# 1. <package_name> <order>
# 2. <package_name> <category> <order> (脚本会自动忽略中间的 category)

CONFIG_FILE="menu_order_list.txt"
FEEDS_DIR="feeds"

# 解析参数
while getopts ":f:" opt; do
  case $opt in
    f)
      CONFIG_FILE="$OPTARG"
      ;;
    \?)
      echo "无效选项: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "选项 -$OPTARG 需要参数." >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

if [ -n "$1" ]; then
    FEEDS_DIR="$1"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 未找到!"
    exit 1
fi

if [ ! -d "$FEEDS_DIR" ]; then
    echo "警告: Feeds 目录 $FEEDS_DIR 未找到。"
fi

echo "开始根据 $CONFIG_FILE 修改菜单排序..."

# 读取配置文件
# 过滤注释和空行
grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | while read -r pkg_name target_order; do
    if [ -z "$pkg_name" ] || [ -z "$target_order" ]; then
        continue
    fi

    # 去除 target_order 可能存在的行尾注释
    target_order=${target_order%%#*}
    # 取最后一个字段作为 order (兼容 <pkg> <order> 和 <pkg> <category> <order>)
    target_order=$(echo "$target_order" | awk '{print $NF}')
    
    # 确保 target_order 是数字
    if ! [[ "$target_order" =~ ^[0-9]+$ ]]; then
        echo "警告: 软件包 $pkg_name 的排序值 '$target_order' 无效，跳过。"
        continue
    fi

    echo "正在处理: $pkg_name -> Order: $target_order"

    # 查找软件包目录
    # 优先精确匹配目录名
    pkg_path=$(find "$FEEDS_DIR" -type d -name "$pkg_name" 2>/dev/null | head -n 1)

    if [ -z "$pkg_path" ]; then
        echo "  -> 未找到软件包目录: $pkg_name"
        continue
    fi

    # --- 1. 修改 Lua Controller 文件 ---
    # 查找该包下的所有 controller lua 文件
    find "$pkg_path" -type f -path "*/luasrc/controller/*.lua" | while read -r lua_file; do
        # 检查文件是否包含 entry
        if grep -q 'entry(' "$lua_file"; then
            # 尝试替换现有的 order
            # 匹配模式: , <digits> )
            # 使用 sed -i -E
            # 注意: 这会将文件中所有的 entry 的 order 都修改为 target_order
            # 对于大多数 luci-app 来说，这通常是可以接受的，因为它们通常属于同一个主菜单项
            
            if grep -qE ',\s*[0-9]+\s*\)' "$lua_file"; then
                sed -i -E "s/,\s*[0-9]+\s*\)/, $target_order)/g" "$lua_file"
                echo "  -> 已更新 Lua: $lua_file"
            else
                # 如果没有找到 order，尝试添加 order (实验性)
                # 假设 entry 结尾是 _("Title")) 或 "Title")
                # 替换 )) 为 , order))
                # 替换 ") 为 ", order)
                # 这是一个比较粗糙的启发式方法
                
                # 检查是否已经有 order (避免重复添加)
                # 上面的 grep 已经检查过了
                
                # 尝试匹配 _("...") )
                if grep -qE '_\("[^"]+"\)\)' "$lua_file"; then
                     sed -i -E "s/_\(\"([^\"]+)\"\)\)/_(\"\1\"), $target_order)/g" "$lua_file"
                     echo "  -> 已添加 Order (Type 1): $lua_file"
                # 尝试匹配 "..." )
                elif grep -qE '"[^"]+"\)' "$lua_file"; then
                     # 排除 "admin", "foo", "bar") 这种路径定义，通常 title 是最后一个字符串
                     # 这里比较危险，暂时只处理明确的 _() 格式，或者不做处理
                     :
                fi
            fi
        fi
    done

    # --- 2. 修改 JSON 菜单定义 ---
    # 查找 menu.d/*.json 或 acl.d/*.json
    find "$pkg_path" -type f \( -path "*/root/usr/share/luci/menu.d/*.json" -o -path "*/root/usr/share/rpcd/acl.d/*.json" \) | while read -r json_file; do
        # 检查是否有 "order": ...
        if grep -q '"order":' "$json_file"; then
            # 替换 order
            sed -i -E "s/\"order\":\s*[0-9]+/\"order\": $target_order/g" "$json_file"
            echo "  -> 已更新 JSON: $json_file"
        fi
    done

done

echo "处理完成。"
