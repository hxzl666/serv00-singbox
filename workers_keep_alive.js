// ============================================================================
// Cloudflare Workers SSH 登录保活与 Telegram 推送脚本
// ============================================================================
// 作用:
//   1. 定期通过 SSH 登录您的 Serv00/Hostuno/Frog VPS 等服务器，防止账号因长期未登录被清理
//   2. 登录成功后可执行自定义命令（如拉起 sing-box/PM2 进程），从而实现服务守护与进程拉起
//   3. 每次巡检完毕后通过 Telegram Bot 发送状态汇总报告
// ============================================================================

import { Client } from 'ssh2';

// [默认配置区]
// 建议优先在 Cloudflare Workers 后台的 Settings -> Variables 中添加同名环境变量！
const DEFAULT_CONFIG = {
  // 账户配置（兼容旧的 SSH 账号格式，且支持额外的 CMD 自定义命令字段）
  ACCOUNTS: [
    {
      SSH_USER: "your_username",
      SSH_PASS: "your_password",
      HOST: "s12.serv00.com",
      PORT: "22",
      CMD: "" // 可选，登录后执行的保活/重启命令（例如: "bash ~/serv00-singbox/keepalive.sh"）。若为空则默认执行 "echo 'keepalive'"
    }
  ],

  // Telegram 通知配置（若不需要通知，可保留为空字符串）
  TELEGRAM_BOT_TOKEN: "", // 填入您的 Telegram Bot Token
  TELEGRAM_CHAT_ID: ""    // 填入您的 Telegram Chat ID
};

// 执行单个 SSH 账号的登录与命令执行
function sshConnectAndCheck(account) {
  return new Promise((resolve) => {
    const conn = new Client();
    const cmd = account.CMD || 'echo "keepalive"';
    
    conn.on('ready', () => {
      // 登录成功，执行指定的保活命令
      conn.exec(cmd, (err, stream) => {
        if (err) {
          conn.end();
          return resolve({ success: false, error: `执行命令失败: ${err.message}` });
        }
        let data = '';
        stream.on('close', (code, signal) => {
          conn.end();
          resolve({ success: true, output: data.trim() });
        }).on('data', (chunk) => {
          data += chunk;
        }).stderr.on('data', (errData) => {
          // 记录可能发生的错误输出
          data += ` [Error: ${errData.toString().trim()}]`;
        });
      });
    }).on('error', (err) => {
      resolve({ success: false, error: err.message });
    }).connect({
      host: account.HOST,
      port: parseInt(account.PORT || '22'),
      username: account.SSH_USER,
      password: account.SSH_PASS,
      readyTimeout: 15000 // 15秒超时
    });
  });
}

// 保活逻辑主函数
async function doKeepAlive(env) {
  let accounts = [];
  
  // 优先从环境变量获取 ACCOUNTS
  if (env && env.ACCOUNTS) {
    try {
      accounts = JSON.parse(env.ACCOUNTS);
    } catch (err) {
      console.error("解析环境变量 ACCOUNTS 失败:", err);
      return { successCount: 0, failCount: 0, message: "环境变量 ACCOUNTS 格式不正确（需为 JSON 数组）" };
    }
  } else {
    accounts = DEFAULT_CONFIG.ACCOUNTS;
  }

  const botToken = (env && env.TELEGRAM_BOT_TOKEN) || DEFAULT_CONFIG.TELEGRAM_BOT_TOKEN;
  const chatId = (env && env.TELEGRAM_CHAT_ID) || DEFAULT_CONFIG.TELEGRAM_CHAT_ID;

  if (!Array.isArray(accounts) || accounts.length === 0) {
    console.log("未配置任何需要保活的 SSH 账户。");
    return { successCount: 0, failCount: 0, message: "未配置任何 SSH 账户" };
  }

  let successCount = 0;
  let failCount = 0;
  let detailMessage = "";

  for (const account of accounts) {
    const label = `${account.SSH_USER}@${account.HOST}:${account.PORT || '22'}`;
    console.log(`正在登录 SSH 保活: ${label}...`);
    
    const startTime = Date.now();
    const result = await sshConnectAndCheck(account);
    const duration = Date.now() - startTime;

    if (result.success) {
      console.log(`成功保活: ${label}, 输出: ${result.output}`);
      detailMessage += `✅ *[OK]* \`${account.SSH_USER}\`@\`${account.HOST}\`\n- 命令: \`${account.CMD || 'echo "keepalive"'}\`\n- 耗时: \`${duration}ms\`\n\n`;
      successCount++;
    } else {
      console.error(`保活失败: ${label}, 错误: ${result.error}`);
      detailMessage += `❌ *[FAIL]* \`${account.SSH_USER}\`@\`${account.HOST}\`\n- 异常: \`${result.error}\`\n- 耗时: \`${duration}ms\`\n\n`;
      failCount++;
    }
  }

  // 组装 Telegram 通知内容
  let reportMessage = "🔔 *Cloudflare Workers SSH 登录保活报告*\n\n";
  reportMessage += `📊 *统计汇总*:\n- 成功: \`${successCount}\` 个\n- 失败: \`${failCount}\` 个\n- 总计: \`${accounts.length}\` 个\n\n`;
  reportMessage += `📝 *详细结果*:\n${detailMessage}`;

  // 发送 Telegram 消息
  if (botToken && chatId) {
    const tgUrl = `https://api.telegram.org/bot${botToken}/sendMessage`;
    try {
      await fetch(tgUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          chat_id: chatId,
          text: reportMessage,
          parse_mode: "Markdown",
          disable_web_page_preview: true
        })
      });
      console.log("Telegram 通知发送成功！");
    } catch (e) {
      console.error("发送 Telegram 通知失败:", e);
    }
  } else {
    console.log("未配置 Telegram 机器人参数，跳过推送通知。");
  }

  return { successCount, failCount };
}

// 导出模块对接 Workers 触发器
export default {
  // 1. 定期 Cron 触发器执行
  async scheduled(event, env, ctx) {
    ctx.waitUntil(doKeepAlive(env));
  },
  
  // 2. 网页/手动 fetch 触发执行 (用于方便测试)
  async fetch(request, env, ctx) {
    const result = await doKeepAlive(env);
    return new Response(JSON.stringify({
      status: "success",
      message: "SSH keep-alive trigger complete.",
      stats: result
    }), {
      headers: { "Content-Type": "application/json" }
    });
  }
};
