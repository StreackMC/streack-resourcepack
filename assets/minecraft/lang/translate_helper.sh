#!/bin/bash
# Deepseek生成

# 颜色定义
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Translate Helper for ${GREEN}MC-JSON${NC}"

# 检查是否提供了文件参数
if [ -z "$1" ]; then
    echo -e "${YELLOW}错误：未提供文件路径${NC}"
    exit 1
fi

# 检查文件是否存在
if [ ! -f "$1" ]; then
    echo -e "${YELLOW}错误：文件 '$1' 不存在${NC}"
    exit 1
fi

# 检查文件扩展名是否为.json
if [[ "$1" != *.json ]]; then
    echo -e "${YELLOW}错误：文件 '$1' 不是JSON文件${NC}"
    exit 1
fi

# 获取文件名和目录
filename=$(basename -- "$1")
dirname=$(dirname -- "$1")
basename="${filename%.*}"

# 创建新的i18n文件名
i18n_file="$dirname/$basename.i18n.json"

# 检查i18n文件是否已存在
if [ ! -f "$i18n_file" ]; then
    # 复制文件
    cp "$1" "$i18n_file"
    echo -e "${GREEN}创建新的翻译工程文件: $i18n_file${NC}"
else
    echo -e "${GREEN}使用现有翻译工程文件: $i18n_file${NC}"
fi
echo -e "${YELLOW}正在打开翻译工程文件${NC}"

# 检查jq是否安装
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}错误：jq命令未安装，请先安装jq${NC}"
    exit 1
fi

# 用于存储上一个键
last_key=""

# 处理函数，实时更新文件
process_key() {
    local key="$1"
    local input="$2"
    
    # 处理跳过逻辑
    if [ "$input" == "." ] || [ "$input" == "。" ]; then
        # 在键名前加上.
        new_key=".$key"
        # 使用jq重命名键并保持值为空
        jq --arg old "$key" --arg new "$new_key" '.[$new] = .[$old] | del(.[$old])' "$i18n_file" > "$i18n_file.tmp"
        mv "$i18n_file.tmp" "$i18n_file"
        echo -e "${GREEN}✓ 已跳过并标记此键${NC}"
        return 0
    # 处理返回上一个键逻辑
    elif [ "$input" == "," ] || [ "$input" == "，" ]; then
        return 1  # 返回1表示需要返回上一个键
    # 处理正常输入
    else
        # 更新键值
        jq --arg k "$key" --arg v "$input" '.[$k] = $v' "$i18n_file" > "$i18n_file.tmp"
        mv "$i18n_file.tmp" "$i18n_file"
        last_key="$key"
        echo -e "${GREEN}$key → $input${NC}"
        echo -e "${GREEN}✓ 已保存${NC}"
        return 0
    fi
}

# 获取所有键并转换为数组
keys=()
while IFS= read -r line; do
    keys+=("$line")
done < <(jq -r 'keys[]' "$i18n_file")

# 处理每个键
i=0
while [ $i -lt ${#keys[@]} ]; do
    key="${keys[$i]}"
    
    # 检查键是否以.开头
    if [[ "$key" == .* ]]; then
        ((i++))
        continue
    fi
    
    # 获取当前键值
    value=$(jq -r --arg k "$key" '.[$k]' "$i18n_file")
    
    # 检查键值是否已有内容
    if [ "$value" != "" ]; then
        ((i++))
        continue
    fi
    
    # 显示键名并获取用户输入
    while true; do
        echo -e "\n${YELLOW}源文本:${NC}"
        echo -e "${WHITE}$key${NC}"
        echo -e "${YELLOW}翻译后:${NC} "
        read -p "$(echo -e "${WHITE}${NC}")" input
        
        if process_key "$key" "$input"; then
            # 处理成功，继续下一个键
            ((i++))
            break
        else
            # 需要返回上一个键
            if [ -n "$last_key" ]; then
                # 找到上一个键的索引
                for ((j=0; j<${#keys[@]}; j++)); do
                    if [ "${keys[$j]}" == "$last_key" ]; then
                        i=$j
                        ((i--))
                        last_key=""  # 重置last_key以避免无限循环
                        echo -e "${YELLOW}返回到上一个键: ${keys[$i]}${NC}"
                        break 2  # 跳出两层循环
                    fi
                done
            else
                echo -e "${YELLOW}没有上一个键可返回${NC}"
            fi
        fi
    done
done

echo -e "\n${GREEN}翻译完成，结果已保存到 $i18n_file${NC}"