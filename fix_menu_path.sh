#!/bin/bash

# 脚本名称: fix_menu_path.sh
# 功能: 根据清单文件修复 LuCI 应用程序的菜单路径
# 用法: ./fix_menu_path.sh [-f list_file] [feeds_dir]

LIST_FILE="menu_path_list.txt"
FEEDS_DIR="feeds"

# 解析参数
while getopts ":f:" opt; do
  case $opt in
    f)
      LIST_FILE="$OPTARG"
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

# 移除已解析的选项参数
shift $((OPTIND-1))

# 剩余的参数作为 feeds 目录
if [ -n "$1" ]; then
    FEEDS_DIR="$1"
fi

if [ ! -f "$LIST_FILE" ]; then
    echo "错误: 清单文件 $LIST_FILE 未找到!"
    exit 1
fi

if [ ! -d "$FEEDS_DIR" ]; then
    echo "警告: Feeds 目录 $FEEDS_DIR 未找到。请确保在正确的目录下运行或指定 feeds 目录。"
    # 不退出，因为可能用户只是想测试或者目录结构不同
fi

echo "开始处理菜单路径..."

# 读取清单文件，忽略注释和空行
grep -vE '^\s*#|^\s*$' "$LIST_FILE" | while read -r pkg_name target_path; do
    if [ -z "$pkg_name" ] || [ -z "$target_path" ]; then
        continue
    fi

    echo "正在检查软件包: $pkg_name (期望路径: $target_path)"

    # 查找软件包路径
    # 搜索 feeds 目录下的所有子目录
    pkg_path=$(find "$FEEDS_DIR" -type d -name "$pkg_name" 2>/dev/null | head -n 1)

    if [ -z "$pkg_path" ]; then
        echo "  -> 未找到软件包目录: $pkg_name"
        continue
    fi

    # 解析目标父级菜单 (Category)
    # 假设 target_path 格式为 "admin/category/name"
    # 我们提取 "category"
    target_category=$(echo "$target_path" | awk -F'/' '{print $2}')
    
    if [ -z "$target_category" ]; then
        echo "  -> 无法从 $target_path 解析出目标分类 (Category)"
        continue
    fi

    # --- 处理 Lua Controller 文件 ---
    lua_files=$(find "$pkg_path" -path "*/luasrc/controller/*.lua")
    
    for lua_file in $lua_files; do
        # 检查文件是否存在
        [ -f "$lua_file" ] || continue

        # 检查是否包含 entry 定义
        if grep -q "entry(" "$lua_file"; then
            # 使用 sed 替换 entry 中的分类
            # 匹配 entry({"admin", "OLD_CATEGORY", ...
            # 替换为 entry({"admin", "NEW_CATEGORY", ...
            
            # 1. 处理双引号 entry({"admin", "xxx", ...
            # 查找当前分类
            current_category_dq=$(sed -n 's/.*entry({"admin", "\([^"]*\)".*/\1/p' "$lua_file" | head -n 1)
            
            if [ -n "$current_category_dq" ] && [ "$current_category_dq" != "$target_category" ]; then
                echo "  -> 修改 Lua (双引号): $lua_file ($current_category_dq -> $target_category)"
                sed -i "s/entry({\"admin\", \"$current_category_dq\"/entry({\"admin\", \"$target_category\"/g" "$lua_file"
            fi

            # 2. 处理单引号 entry({'admin', 'xxx', ...
            current_category_sq=$(sed -n "s/.*entry({'admin', '\([^']*\)'.*/\1/p" "$lua_file" | head -n 1)
            
            if [ -n "$current_category_sq" ] && [ "$current_category_sq" != "$target_category" ]; then
                echo "  -> 修改 Lua (单引号): $lua_file ($current_category_sq -> $target_category)"
                sed -i "s/entry({'admin', '$current_category_sq'/entry({'admin', '$target_category'/g" "$lua_file"
            fi
            
            # 3. 处理混合引号或空格 (简单处理)
            # 如果上面没匹配到，尝试更宽泛的匹配
            # sed -i "s/entry({\"admin\", \"[^\"]*\"/entry({\"admin\", \"$target_category\"/g" "$lua_file"
        fi
    done

    # --- 处理 JSON 菜单定义 (新版 LuCI) ---
    # 路径通常在 root/usr/share/luci/menu.d/*.json
    json_files=$(find "$pkg_path" -path "*/root/usr/share/luci/menu.d/*.json")
    
    for json_file in $json_files; do
        [ -f "$json_file" ] || continue
        
        # JSON key 格式通常是 "admin/category/name"
        # 我们需要替换 key 中的 category 部分
        
        # 读取文件内容，查找包含 "admin/" 的键
        # 这里使用 sed 直接替换可能比较危险，因为可能匹配到值
        # 但 key 通常在行首附近
        
        # 查找当前的 category
        # 匹配 "admin/xxx/
        if grep -q "\"admin/" "$json_file"; then
             # 尝试提取当前 category
             # 假设格式 "admin/old_cat/name":
             current_cat_json=$(sed -n 's/.*"admin\/\([^/]*\)\/.*/\1/p' "$json_file" | head -n 1)
             
             if [ -n "$current_cat_json" ] && [ "$current_cat_json" != "$target_category" ]; then
                 echo "  -> 修改 JSON: $json_file ($current_cat_json -> $target_category)"
                 sed -i "s/\"admin\/$current_cat_json\//\"admin\/$target_category\//g" "$json_file"
             fi
        fi
    done

done

echo "处理完成。"
