#!/usr/bin/env node

/**
 * 文本组件迁移工具，遍历指定目录下全部 .mcfunction 文件并自动更新其中的旧版文本组件到 1.21.5+
 * @author 由 Deepseek 生成。
 */

import { readFileSync, copyFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'fs';
import { join } from 'path';

// ---------- 转换核心 ----------
function convertComponent(comp) {
    if (typeof comp === 'string') return comp;
    if (Array.isArray(comp)) {
        return comp.map(item => convertComponent(item));
    }
    if (typeof comp === 'object' && comp !== null) {
        const result = {};

        // 先复制所有键，同时处理 clickEvent / hoverEvent 重命名
        for (let [key, value] of Object.entries(comp)) {
            let newKey = key;
            if (key === 'clickEvent') newKey = 'click_event';
            else if (key === 'hoverEvent') newKey = 'hover_event';
            // 其他键保持不变
            result[newKey] = convertComponent(value);
        }

        // 处理 click_event 内部
        if (result.click_event && typeof result.click_event === 'object') {
            const ev = result.click_event;
            if (ev.action && ev.value !== undefined) {
                const action = ev.action;
                if (action === 'open_url') {
                    ev.url = ev.value;
                    delete ev.value;
                } else if (action === 'run_command' || action === 'suggest_command') {
                    ev.command = ev.value;
                    delete ev.value;
                } else if (action === 'change_page') {
                    ev.page = parseInt(ev.value, 10);
                    delete ev.value;
                }
                // copy_to_clipboard 保持 value 不变
            }
        }

        // 处理 hover_event 内部
        if (result.hover_event && typeof result.hover_event === 'object') {
            const ev = result.hover_event;
            if (ev.action) {
                const action = ev.action;
                if (action === 'show_text') {
                    // 统一使用 value
                    if (ev.contents !== undefined) {
                        ev.value = ev.contents;
                        delete ev.contents;
                    }
                    // 如果已有 value 则保持不变
                } else if (action === 'show_item') {
                    if (ev.contents !== undefined) {
                        const contents = ev.contents;
                        delete ev.contents;
                        // 将 contents 的属性提升到 ev 上
                        Object.assign(ev, contents);
                    } else if (ev.value !== undefined) {
                        // 旧格式可能用 value 字符串，此时无法自动解析，保留 value 并警告
                        console.warn('  [WARN] show_item with value string, may need manual fix:', ev.value);
                    }
                } else if (action === 'show_entity') {
                    if (ev.contents !== undefined) {
                        const contents = ev.contents;
                        delete ev.contents;
                        // 重命名 id -> uuid, type -> id
                        if (contents.id !== undefined) {
                            contents.uuid = contents.id;
                            delete contents.id;
                        }
                        if (contents.type !== undefined) {
                            contents.id = contents.type;
                            delete contents.type;
                        }
                        Object.assign(ev, contents);
                    } else if (ev.value !== undefined) {
                        console.warn('  [WARN] show_entity with value string, may need manual fix:', ev.value);
                    }
                }
            }
        }

        return result;
    }
    return comp; // fallback
}

// ---------- 序列化为 SNBT 字符串 ----------
function toSNBT(val) {
    if (typeof val === 'string') {
        // 转义双引号和反斜杠
        return '"' + val.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
    }
    if (typeof val === 'number' || typeof val === 'boolean') {
        return String(val);
    }
    if (Array.isArray(val)) {
        return '[' + val.map(v => toSNBT(v)).join(', ') + ']';
    }
    if (typeof val === 'object' && val !== null) {
        const parts = Object.keys(val).map(k => {
            // 键名必须符合标识符规则，此处直接使用
            return k + ':' + toSNBT(val[k]);
        });
        return '{' + parts.join(', ') + '}';
    }
    return 'null'; // 实际上不会出现
}

// ---------- 从命令中提取文本组件参数 ----------
function extractComponentFromLine(line) {
    // 去掉行尾空格
    let trimmed = line.trimRight();
    // 尝试匹配常见命令
    let match = null;
    let cmd = '';
    let argStr = '';

    // tellraw
    match = trimmed.match(/^(tellraw)\s+\S+\s+(.+)$/);
    if (match) {
        cmd = 'tellraw';
        argStr = match[2];
    }
    // title
    if (!match) {
        match = trimmed.match(/^(title)\s+\S+\s+\S+\s+(.+)$/);
        if (match) {
            cmd = 'title';
            argStr = match[2];
        }
    }
    // bossbar set ... name
    if (!match) {
        match = trimmed.match(/^(bossbar)\s+set\s+\S+\s+name\s+(.+)$/);
        if (match) {
            cmd = 'bossbar';
            argStr = match[2];
        }
    }

    if (!match) return null; // 不是这些命令

    // 去除 argStr 首尾空格
    argStr = argStr.trim();
    return { cmd, argStr, prefix: trimmed.slice(0, trimmed.length - argStr.length) };
}

// ---------- 尝试解析文本组件 ----------
function parseArgument(argStr) {
    // 尝试直接解析为 JSON
    try {
        const parsed = JSON.parse(argStr);
        return { parsed, raw: argStr, type: 'json' };
    } catch (e) {
        // 可能是带引号的 JSON 字符串
        if (argStr.startsWith('"') && argStr.endsWith('"')) {
            // 去掉外层引号后尝试解析
            try {
                const inner = JSON.parse(argStr);
                // 如果 inner 是字符串，则原样保留
                if (typeof inner === 'string') {
                    return { parsed: inner, raw: argStr, type: 'string' };
                }
                // 否则是对象/数组，转换后需要去掉外层引号
                return { parsed: inner, raw: argStr, type: 'json_string' };
            } catch (e2) {
                // 不是有效JSON，当作纯字符串
                return { parsed: argStr, raw: argStr, type: 'string' };
            }
        }
        // 可能纯文本（无引号）
        return { parsed: argStr, raw: argStr, type: 'plain' };
    }
}

// ---------- 处理一行命令 ----------
function processLine(line) {
    const info = extractComponentFromLine(line);
    if (!info) return line;

    const { cmd, argStr, prefix } = info;
    const parsedInfo = parseArgument(argStr);
    let newArg = null;

    // 如果是纯字符串或 plain，保持不变
    if (parsedInfo.type === 'string' || parsedInfo.type === 'plain') {
        newArg = argStr; // 保持原样
    } else {
        // 需要转换
        const comp = parsedInfo.parsed;
        const converted = convertComponent(comp);
        newArg = toSNBT(converted);
        // 如果原始参数是 JSON 字符串（带外层引号），则新参数不加引号
        // 如果原始参数是对象/数组，直接替换
        // 否则（plain）也直接替换
    }

    // 重建行
    return prefix + newArg;
}

// ---------- 处理文件 ----------
function processFile(filePath) {
    console.log(`Processing ${filePath}`);
    const content = readFileSync(filePath, 'utf8');
    const lines = content.split(/\r?\n/);
    let changed = false;
    const newLines = lines.map(line => {
        const newLine = processLine(line);
        if (newLine !== line) changed = true;
        return newLine;
    });

    if (changed) {
        // 备份
        const backup = filePath + '.bak';
        copyFileSync(filePath, backup);
        console.log(`  Backup created: ${backup}`);
        writeFileSync(filePath, newLines.join('\n'), 'utf8');
        console.log(`  Updated: ${filePath}`);
    } else {
        console.log(`  No changes in ${filePath}`);
    }
}

// ---------- 遍历目录 ----------
function walkDir(dir, callback) {
    const files = readdirSync(dir);
    for (const file of files) {
        const fullPath = join(dir, file);
        const stat = statSync(fullPath);
        if (stat.isDirectory()) {
            walkDir(fullPath, callback);
        } else if (stat.isFile() && file.endsWith('.mcfunction')) {
            callback(fullPath);
        }
    }
}

// ---------- 主程序 ----------
function main() {
    const rootDir = process.argv[2] || '.';
    if (!existsSync(rootDir)) {
        console.error(`Directory ${rootDir} does not exist.`);
        process.exit(1);
    }
    console.log(`Scanning ${rootDir} for .mcfunction files...`);
    walkDir(rootDir, processFile);
    console.log('Done.');
}

main();